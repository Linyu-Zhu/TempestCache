`timescale 1ns/1ps

module dcache #(
    parameter DATA_WIDTH = 32,      // ���ݿ��
    parameter ADDR_WIDTH = 32,      // ��ַ���
    parameter CACHE_SIZE = 1024,    // �����С���ֽڣ�
    parameter BLOCK_SIZE = 16       // ���С���ֽڣ�
)(
    input  logic clk,               // ʱ���ź�
    input  logic rst_n,             // �첽��λ������Ч��
    
    // CPU�ӿ�
    input  logic cpu_req,           // CPU�����ź�
    input  logic cpu_we,            // CPUдʹ��
    input  logic [ADDR_WIDTH-1:0] cpu_addr, // CPU��ַ
    input  logic [DATA_WIDTH-1:0] cpu_wdata, // CPUд����
    output logic cpu_ready,         // CPU�����ź�
    output logic [DATA_WIDTH-1:0] cpu_rdata, // CPU������
    output logic cpu_hit,           // CPU�����ź�
    
    // �ڴ�ӿ�
    output logic mem_req,           // �ڴ������ź�
    output logic mem_we,            // �ڴ�дʹ��
    output logic [ADDR_WIDTH-1:0] mem_addr, // �ڴ��ַ
    output logic [DATA_WIDTH-1:0] mem_wdata, // �ڴ�д����
    input  logic mem_ready,         // �ڴ�����ź�
    input  logic [DATA_WIDTH-1:0] mem_rdata  // �ڴ������
);

    // �������
    localparam NUM_BLOCKS = CACHE_SIZE / BLOCK_SIZE; // ���������
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);     // ƫ����λ��
    localparam INDEX_BITS = $clog2(NUM_BLOCKS);      // ����λ��
    localparam TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS; // ��ǩλ��
    
    // �����нṹ
    typedef struct packed {
        logic valid;                // ��Чλ
        logic dirty;                // ��λ��д�ز�����Ҫ��
        logic [TAG_BITS-1:0] tag;    // ��ǩ
        logic [DATA_WIDTH-1:0] data; // ����
    } cache_line_t;
    
    // ��������
    cache_line_t cache [NUM_BLOCKS];
    
    // ״̬������
    enum logic [1:0] {
        IDLE,                       // ����״̬
        WRITE_BACK,                 // д��״̬
        FILL                        // ���״̬
    } state, next_state;
    
    // ��ַ�ֽ�
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    
    assign tag = cpu_addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS];
    assign index = cpu_addr[ADDR_WIDTH-TAG_BITS-1:OFFSET_BITS];
    assign offset = cpu_addr[OFFSET_BITS-1:0];
    
    // ��ǰ������
    cache_line_t current_line;
    assign current_line = cache[index];
    
    // �����ж�
    logic hit;
    assign hit = current_line.valid && (current_line.tag == tag);
    
    // ״̬���Ĵ���
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // �����ʼ������λʱ��
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_BLOCKS; i++) begin
                cache[i] <= '{valid: 1'b0, dirty: 1'b0, tag: '0, data: '0};
            end
        end else if (state == FILL && mem_ready) begin
            // ��仺����
            cache[index] <= '{valid: 1'b1, dirty: 1'b0, tag: tag, data: mem_rdata};
        end else if (state == IDLE && cpu_req && cpu_we && hit) begin
            // д����ʱ���»���
            cache[index].data <= cpu_wdata;
            cache[index].dirty <= 1'b1; // д�ز��ԣ�������λ
        end
    end
    
    // ״̬��ת���߼�
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        next_state = IDLE; // ����ֱ�Ӵ���
                    end else begin
                        // δ���У�����Ƿ���Ҫд��
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
                    next_state = FILL; // д����ɺ����������
                end
            end
            
            FILL: begin
                if (mem_ready) begin
                    next_state = IDLE; // �����ɺ�ص�����״̬
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // ��������߼�
    always_comb begin
        // Ĭ��ֵ
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
                        cpu_ready = 1'b1; // ����ʱ������Ӧ
                    end else begin
                        // δ���У���Ҫ�����ڴ�
                        if (current_line.valid && current_line.dirty) begin
                            // ��Ҫ��д��
                            mem_req = 1'b1;
                            mem_we = 1'b1;
                            // д�ص�ַ�ɵ�ǰ�����е�tag��index���
                            mem_addr = {current_line.tag, index, {OFFSET_BITS{1'b0}}};
                        end else begin
                            // ֱ�����
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
                    cpu_ready = 1'b1; // �����ɺ���ӦCPU
                    cpu_rdata = mem_rdata;
                end
            end
            
            default: ;
        endcase
    end

endmodule