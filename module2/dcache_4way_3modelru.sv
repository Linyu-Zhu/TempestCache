`timescale 1ns/1ps

module dcache #(
    parameter DATA_WIDTH = 32,      // 数据宽度
    parameter ADDR_WIDTH = 32,      // 地址宽度
    parameter CACHE_SIZE = 1024,    // 缓存大小(字节)
    parameter BLOCK_SIZE = 16,      // 块大小(字节)
    parameter WRITE_POLICY = 0,     // 0: 写直达, 1: 写回
    parameter DEBUG = 1,            // 调试模式
    parameter HISTORY_SIZE = 4      // 历史记录大小(4-8)
)(
    input  logic clk,               // 时钟
    input  logic rst_n,             // 异步复位(低有效)
    
    // CPU接口
    input  logic cpu_req,           // CPU请求
    input  logic cpu_we,            // CPU写使能
    input  logic [ADDR_WIDTH-1:0] cpu_addr, // CPU地址
    input  logic [DATA_WIDTH-1:0] cpu_wdata, // CPU写数据
    output logic cpu_ready,         // CPU就绪
    output logic [DATA_WIDTH-1:0] cpu_rdata, // CPU读数据
    output logic cpu_hit,           // CPU命中信号
    
    // 内存接口
    output logic mem_req,           // 内存请求
    output logic mem_we,            // 内存写使能
    output logic [ADDR_WIDTH-1:0] mem_addr, // 内存地址
    output logic [DATA_WIDTH-1:0] mem_wdata, // 内存写数据
    input  logic mem_ready,         // 内存就绪
    input  logic [DATA_WIDTH-1:0] mem_rdata  // 内存读数据
);

    // 缓存参数计算
    localparam NUM_WAYS = 4;                            // 路数
    localparam NUM_SETS = CACHE_SIZE/(BLOCK_SIZE*NUM_WAYS); // 组数
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);       // 偏移位
    localparam INDEX_BITS = $clog2(NUM_SETS);          // 索引位
    localparam TAG_BITS = ADDR_WIDTH-INDEX_BITS-OFFSET_BITS; // 标签位
    
    // 扩展的缓存行结构
    typedef struct packed {
        logic valid;                // 有效位
        logic dirty;                // 脏位
        logic [TAG_BITS-1:0] tag;   // 标签
        logic [DATA_WIDTH-1:0] data; // 数据
        logic [1:0] access_type;    // 访问类型: 0=Normal, 1=Periodic, 2=Hot
    } cache_line_t;
    
    // 访问历史记录结构
    typedef struct packed {
        logic [TAG_BITS-1:0] tag;   // 标签
        logic [INDEX_BITS-1:0] index; // 组索引
        logic valid;                // 有效位
    } history_entry_t;
    
    // 缓存存储器
    cache_line_t cache [NUM_SETS][NUM_WAYS];
    
    // 历史记录表(每组一个)
    history_entry_t history [NUM_SETS][HISTORY_SIZE];
    logic [3:0] history_ptr [NUM_SETS]; // 历史记录指针
    
    // LRU位向量
    typedef logic [NUM_WAYS*NUM_WAYS-1:0] lru_bits_t;
    lru_bits_t lru_bits [NUM_SETS];
    
    // 状态机
    enum logic [1:0] {IDLE, WRITE_BACK, FILL} state, next_state;
    
    // 地址分解
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    
    assign tag = cpu_addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS];
    assign index = cpu_addr[ADDR_WIDTH-TAG_BITS-1:OFFSET_BITS];
    assign offset = cpu_addr[OFFSET_BITS-1:0];
    
    // 命中检测
    logic [NUM_WAYS-1:0] way_hits;
    logic hit;
    integer way_idx;
    
    // 计算每路的命中情况
    always_comb begin
        way_hits = '0;
        for (int i = 0; i < NUM_WAYS; i++) begin
            way_hits[i] = cache[index][i].valid && (cache[index][i].tag == tag);
        end
        hit = |way_hits;
        
        // 找到命中的路
        way_idx = 0;
        for (int i = 0; i < NUM_WAYS; i++) begin
            if (way_hits[i]) way_idx = i;
        end
    end
    
    // 查找LRU路
    function automatic integer find_lru_way(logic [NUM_WAYS*NUM_WAYS-1:0] lru);
        integer max_count = -1;
        integer lru_way = 0;
        for (int i = 0; i < NUM_WAYS; i++) begin
            integer count = 0;
            for (int j = 0; j < NUM_WAYS; j++) begin
                if (i != j && lru[i*NUM_WAYS + j]) count++;
            end
            if (count > max_count) begin
                max_count = count;
                lru_way = i;
            end
        end
        return lru_way;
    endfunction
    
    // 更新LRU位 - 使指定路成为MRU
    function automatic lru_bits_t update_lru(lru_bits_t lru, input integer way);
        lru_bits_t new_lru = lru;
        for (int i = 0; i < NUM_WAYS; i++) begin
            if (i != way) begin
                new_lru[way*NUM_WAYS + i] = 1;  // way比i新
                new_lru[i*NUM_WAYS + way] = 0;  // i比way旧
            end
        end
        return new_lru;
    endfunction
    
    // 模式检测函数
    function automatic logic [1:0] detect_pattern(
        input history_entry_t history[HISTORY_SIZE],
        input logic [TAG_BITS-1:0] current_tag,
        input logic [INDEX_BITS-1:0] current_index
    );
        integer hot_count = 0;
        integer periodic_count = 0;
        integer i, j;
        
        // 热点检测: 统计历史记录中相同标签的出现次数
        for (i = 0; i < HISTORY_SIZE; i++) begin
            if (history[i].valid && history[i].tag == current_tag)
                hot_count++;
        end
        
        // 周期性检测: 检查是否存在循环访问模式
        for (i = 0; i < HISTORY_SIZE-1; i++) begin
            if (!history[i].valid || !history[i+1].valid) continue;
            for (j = i+1; j < HISTORY_SIZE; j++) begin
                if (history[j].valid &&
                    history[j].tag == history[i].tag &&
                    history[j+1 >= HISTORY_SIZE ? 0 : j+1].valid &&
                    history[j+1 >= HISTORY_SIZE ? 0 : j+1].tag == history[i+1].tag) begin
                    periodic_count++;
                end
            end
        end
        
        // 决策逻辑: 热点优先于周期性
        if (hot_count >= 2) return 2'b10;      // Hot
        else if (periodic_count >= 1) return 2'b01; // Periodic
        else return 2'b00;                    // Normal
    endfunction
    
    // 选择替换路 - 基于模式和LRU

function automatic integer select_victim(
    input cache_line_t ways[NUM_WAYS],
    input lru_bits_t lru,
    input logic [1:0] pattern
);
    integer victim = 0;
    integer min_replace_priority = 100; // 初始化为最大值
    
    for (int i = 0; i < NUM_WAYS; i++) begin
        int unsigned replace_priority;    // 替换优先级
        int unsigned lru_order;           // LRU顺序
        
        // 计算该路的LRU顺序 (0=MRU, 3=LRU)
        lru_order = 0;
        for (int j = 0; j < NUM_WAYS; j++) begin
            if (i != j && lru[i*NUM_WAYS + j])
                lru_order++;
        end
        
        // 计算替换优先级:
        // 1. 优先替换无效行
        // 2. 优先替换Normal类型
        // 3. 同类型按LRU顺序
        if (!ways[i].valid) begin
            replace_priority = 0; // 最低优先级(优先替换)
        end else begin
            // 优先级: Normal < Periodic < Hot
            replace_priority = (ways[i].access_type * 10) + lru_order;
        end
        
        if (replace_priority < min_replace_priority) begin
            min_replace_priority = replace_priority;
            victim = i;
        end
    end
    
    return victim;
endfunction
    
    // 状态寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // 当前操作的路
    integer current_way;
    
    // 缓存初始化和更新逻辑
    integer i, j;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始化缓存
            for (i = 0; i < NUM_SETS; i++) begin
                for (j = 0; j < NUM_WAYS; j++) begin
                    cache[i][j] <= '{valid: 1'b0, dirty: 1'b0, tag: '0, data: '0, access_type: 2'b00};
                end
                
                // 初始化历史记录
                for (j = 0; j < HISTORY_SIZE; j++) begin
                    history[i][j] <= '{tag: '0, index: '0, valid: 1'b0};
                end
                history_ptr[i] <= 0;
                
                // 初始化LRU位
                lru_bits[i] <= '0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (hit) begin
                            // 命中: 更新LRU位
                            lru_bits[index] <= update_lru(lru_bits[index], way_idx);
                            
                            // 更新访问类型
                            cache[index][way_idx].access_type <= detect_pattern(
                                history[index], tag, index);
                            
                            if (cpu_we) begin
                                // 写命中
                                cache[index][way_idx].data <= cpu_wdata;
                                cache[index][way_idx].dirty <= (WRITE_POLICY) ? 1'b1 : 1'b0;
                                
                                if (DEBUG && WRITE_POLICY)
                                    $display("[%0t] CACHE: Write hit - set=%0d, way=%0d, tag=%0h, data=%0h",
                                            $time, index, way_idx, tag, cpu_wdata);
                            end
                        end else begin
                            // 未命中: 更新历史记录
                            history[index][history_ptr[index]] <= '{tag: tag, index: index, valid: 1'b1};
                            history_ptr[index] <= (history_ptr[index] + 1) % HISTORY_SIZE;
                            
                            // 基于模式选择替换路
                            current_way <= select_victim(
                                cache[index], lru_bits[index],
                                detect_pattern(history[index], tag, index));
                        end
                    end
                end
                
                WRITE_BACK: begin
                    if (mem_ready) begin
                        // 写回完成，开始填充
                        // 更新LRU位
                        lru_bits[index] <= update_lru(lru_bits[index], current_way);
                    end
                end
                
                FILL: begin
                    if (mem_ready) begin
                        // 填充缓存行，同时设置访问类型
                        logic [1:0] pattern = detect_pattern(history[index], tag, index);
                        
                        if (cpu_we) begin
                            // 写操作
                            cache[index][current_way] <= '{
                                valid: 1'b1,
                                dirty: (WRITE_POLICY) ? 1'b1 : 1'b0,
                                tag: tag,
                                data: cpu_wdata,
                                access_type: pattern
                            };
                            if (DEBUG)
                                $display("[%0t] CACHE: Fill with write - set=%0d, way=%0d, tag=%0h, data=%0h, type=%b",
                                        $time, index, current_way, tag, cpu_wdata, pattern);
                        end else begin
                            // 读操作
                            cache[index][current_way] <= '{
                                valid: 1'b1,
                                dirty: 1'b0,
                                tag: tag,
                                data: mem_rdata,
                                access_type: pattern
                            };
                            if (DEBUG)
                                $display("[%0t] CACHE: Fill with read - set=%0d, way=%0d, tag=%0h, data=%0h, type=%b",
                                        $time, index, current_way, tag, mem_rdata, pattern);
                        end
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    // 状态转换逻辑(保持不变)
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        next_state = IDLE; // 命中，保持空闲
                    end else begin
                        // 未命中，检查是否需要写回
                        if (cache[index][current_way].valid && cache[index][current_way].dirty && WRITE_POLICY) begin
                            next_state = WRITE_BACK;
                        end else begin
                            next_state = FILL;
                        end
                    end
                end
            end
            
            WRITE_BACK: begin
                if (mem_ready) begin
                    next_state = FILL; // 写回后，进入填充状态
                end
            end
            
            FILL: begin
                if (mem_ready) begin
                    next_state = IDLE; // 填充后，返回空闲状态
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // 输出控制逻辑(保持不变)
    always_comb begin
        // 默认值
        cpu_ready = 1'b0;
        cpu_rdata = '0;
        cpu_hit = hit;
        mem_req = 1'b0;
        mem_we = 1'b0;
        mem_addr = '0;
        mem_wdata = '0;
        
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        if (WRITE_POLICY == 0 && cpu_we) begin
                            // 写直达: 立即写入内存
                            mem_req = 1'b1;
                            mem_we = 1'b1;
                            mem_addr = {cache[index][way_idx].tag, index, {OFFSET_BITS{1'b0}}};
                            mem_wdata = cpu_wdata;
                            if (DEBUG)
                                $display("[%0t] CACHE: Write-through - set=%0d, way=%0d, tag=%0h, data=%0h",
                                        $time, index, way_idx, cache[index][way_idx].tag, cpu_wdata);
                        end
                        cpu_ready = 1'b1; // 命中，立即就绪
                        cpu_rdata = cache[index][way_idx].data;
                    end
                end
            end
            
            WRITE_BACK: begin
                mem_req = 1'b1;
                mem_we = 1'b1;
                mem_addr = {cache[index][current_way].tag, index, {OFFSET_BITS{1'b0}}};
                mem_wdata = cache[index][current_way].data;
                if (DEBUG)
                    $display("[%0t] CACHE: Write-back - set=%0d, way=%0d, tag=%0h, data=%0h",
                            $time, index, current_way, cache[index][current_way].tag, cache[index][current_way].data);
            end
            
            FILL: begin
                mem_req = 1'b1;
                mem_we = cpu_we && (WRITE_POLICY == 0); // 写直达模式下写入
                mem_addr = {tag, index, {OFFSET_BITS{1'b0}}};
                mem_wdata = cpu_wdata;
                
                if (DEBUG) begin
                    if (cpu_we && WRITE_POLICY == 0)
                        $display("[%0t] MEM: Write - set=%0d, way=%0d, tag=%0h, data=%0h",
                                $time, index, current_way, tag, cpu_wdata);
                    else if (!cpu_we)
                        $display("[%0t] MEM: Read - set=%0d, way=%0d, tag=%0h, data=%0h",
                                $time, index, current_way, tag, mem_rdata);
                end
                
                if (mem_ready) begin
                    cpu_ready = 1'b1;
                    cpu_rdata = mem_rdata;
                end
            end
            
            default: ;
        endcase
    end

endmodule