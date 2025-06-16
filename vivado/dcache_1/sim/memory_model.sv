module memory_model #(
    parameter LATENCY = 10
)(
    input  logic clk,
    input  logic rst_n,
    input  logic mem_req,
    input  logic mem_we,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    output logic mem_ready,
    output logic [31:0] mem_rdata
);

    // 模拟内存延迟
    integer delay_counter = 0;
    logic [31:0] memory [0:1023]; // 1KB内存

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready <= 0;
            delay_counter <= 0;
            // 初始化内存内容
            for (int i = 0; i < 1024; i++) begin
                memory[i] <= i;
            end
        end else begin
            if (mem_req && !mem_ready) begin
                if (delay_counter == LATENCY-1) begin
                    mem_ready <= 1;
                    delay_counter <= 0;
                    if (mem_we) begin
                        memory[mem_addr >> 2] <= mem_wdata; // 字寻址
                        $display("[%0t] MEM Write: addr=%0h, data=%0h", $time, mem_addr, mem_wdata);
                    end else begin
                        mem_rdata <= memory[mem_addr >> 2];
                        $display("[%0t] MEM Read: addr=%0h, data=%0h", $time, mem_addr, mem_rdata);
                    end
                end else begin
                    delay_counter <= delay_counter + 1;
                end
            end else begin
                mem_ready <= 0;
            end
        end
    end

endmodule