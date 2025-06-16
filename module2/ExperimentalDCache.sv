`timescale 1ns/1ps

module dcache #(
    parameter DATA_WIDTH = 32,      // 数据宽度
    parameter ADDR_WIDTH = 32,      // 地址宽度
    parameter CACHE_SIZE = 1024,    // 缓存大小（字节）
    parameter BLOCK_SIZE = 16       // 块大小（字节）
)(
    input  logic clk,               // 时钟信号
    input  logic rst_n,             // 异步复位（低有效）
    
    // CPU接口
    input  logic cpu_req,           // CPU请求信号
    input  logic cpu_we,            // CPU写使能
    input  logic [ADDR_WIDTH-1:0] cpu_addr, // CPU地址
    input  logic [DATA_WIDTH-1:0] cpu_wdata, // CPU写数据
    output logic cpu_ready,         // CPU就绪信号
    output logic [DATA_WIDTH-1:0] cpu_rdata, // CPU读数据
    output logic cpu_hit,           // CPU命中信号
    
    // 内存接口
    output logic mem_req,           // 内存请求信号
    output logic mem_we,            // 内存写使能
    output logic [ADDR_WIDTH-1:0] mem_addr, // 内存地址
    output logic [DATA_WIDTH-1:0] mem_wdata, // 内存写数据
    input  logic mem_ready,         // 内存就绪信号
    input  logic [DATA_WIDTH-1:0] mem_rdata  // 内存读数据
);

    // 计算参数
    localparam NUM_BLOCKS = CACHE_SIZE / BLOCK_SIZE; // 缓存块数量
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);     // 偏移量位数
    localparam INDEX_BITS = $clog2(NUM_BLOCKS);      // 索引位数
    localparam TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS; // 标签位数
    
    // 缓存行结构
    typedef struct packed {
        logic valid;                // 有效位
        logic dirty;                // 脏位（写回策略需要）
        logic [TAG_BITS-1:0] tag;    // 标签
        logic [DATA_WIDTH-1:0] data; // 数据
    } cache_line_t;
    
    // 缓存阵列
    cache_line_t cache [NUM_BLOCKS];
    
    // 状态机定义
    enum logic [1:0] {
        IDLE,                       // 空闲状态
        WRITE_BACK,                 // 写回状态
        FILL                        // 填充状态
    } state, next_state;
    
    // 地址分解
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    
    assign tag = cpu_addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS];
    assign index = cpu_addr[ADDR_WIDTH-TAG_BITS-1:OFFSET_BITS];
    assign offset = cpu_addr[OFFSET_BITS-1:0];
    
    // 当前缓存行
    cache_line_t current_line;
    assign current_line = cache[index];
    
    // 命中判断
    logic hit;
    assign hit = current_line.valid && (current_line.tag == tag);
    
    // 状态机寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // 缓存初始化（复位时）
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_BLOCKS; i++) begin
                cache[i] <= '{valid: 1'b0, dirty: 1'b0, tag: '0, data: '0};
            end
        end else if (state == FILL && mem_ready) begin
            // 填充缓存行
            cache[index] <= '{valid: 1'b1, dirty: 1'b0, tag: tag, data: mem_rdata};
        end else if (state == IDLE && cpu_req && cpu_we && hit) begin
            // 写命中时更新缓存
            cache[index].data <= cpu_wdata;
            cache[index].dirty <= 1'b1; // 写回策略：设置脏位
        end
    end
    
    // 状态机转换逻辑
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        next_state = IDLE; // 命中直接处理
                    end else begin
                        // 未命中：检查是否需要写回
                        if (current_line.valid && current_line.dirty) begin
                            next_state = WRITE_BACK;
                        end else begin
                            next_state = FILL;
                        end
                    end
                end
            end
            
            WRITE_BACK: begin
                if (mem_ready) begin
                    next_state = FILL; // 写回完成后填充新数据
                end
            end
            
            FILL: begin
                if (mem_ready) begin
                    next_state = IDLE; // 填充完成后回到空闲状态
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // 输出控制逻辑
    always_comb begin
        // 默认值
        cpu_ready = 1'b0;
        cpu_rdata = current_line.data;
        cpu_hit = hit;
        mem_req = 1'b0;
        mem_we = 1'b0;
        mem_addr = '0;
        mem_wdata = current_line.data;
        
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        cpu_ready = 1'b1; // 命中时立即响应
                    end else begin
                        // 未命中：需要访问内存
                        if (current_line.valid && current_line.dirty) begin
                            // 需要先写回
                            mem_req = 1'b1;
                            mem_we = 1'b1;
                            // 写回地址由当前缓存行的tag和index组成
                            mem_addr = {current_line.tag, index, {OFFSET_BITS{1'b0}}};
                        end else begin
                            // 直接填充
                            mem_req = 1'b1;
                            mem_we = 1'b0;
                            mem_addr = {tag, index, {OFFSET_BITS{1'b0}}};
                        end
                    end
                end
            end
            
            WRITE_BACK: begin
                mem_req = 1'b1;
                mem_we = 1'b1;
                mem_addr = {current_line.tag, index, {OFFSET_BITS{1'b0}}};
            end
            
            FILL: begin
                mem_req = 1'b1;
                mem_we = 1'b0;
                mem_addr = {tag, index, {OFFSET_BITS{1'b0}}};
                if (mem_ready) begin
                    cpu_ready = 1'b1; // 填充完成后响应CPU
                    cpu_rdata = mem_rdata;
                end
            end
            
            default: ;
        endcase
    end

endmodule