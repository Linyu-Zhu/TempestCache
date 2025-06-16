`timescale 1ns/1ps

module tb_dcache();

    // 参数与缓存设计一致
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter CACHE_SIZE = 1024;
    parameter BLOCK_SIZE = 16;
    parameter WRITE_POLICY = 1; // 测试写回模式

    // 时钟和复位
    logic clk;
    logic rst_n;

    // CPU接口
    logic cpu_req;
    logic cpu_we;
    logic [ADDR_WIDTH-1:0] cpu_addr;
    logic [DATA_WIDTH-1:0] cpu_wdata;
    logic cpu_ready;
    logic [DATA_WIDTH-1:0] cpu_rdata;
    logic cpu_hit;

    // 内存接口
    logic mem_req;
    logic mem_we;
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic [DATA_WIDTH-1:0] mem_wdata;
    logic mem_ready;
    logic [DATA_WIDTH-1:0] mem_rdata;

    // 实例化缓存
    dcache #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .CACHE_SIZE(CACHE_SIZE),
        .BLOCK_SIZE(BLOCK_SIZE),
        .WRITE_POLICY(WRITE_POLICY),
        .DEBUG(1)
    ) u_dcache (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready),
        .cpu_rdata(cpu_rdata),
        .cpu_hit(cpu_hit),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata)
    );

    // 内存模型（模拟延迟）
    memory_model #(
        .LATENCY(10) // 内存访问延迟10周期
    ) u_memory (
        .clk(clk),
        .rst_n(rst_n),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz时钟
    end

    // 复位初始化
    initial begin
        rst_n = 0;
        #20 rst_n = 1;
    end

    // 测试逻辑
    integer total_access = 0;
    integer hit_count = 0;
    integer total_cycles = 0;

    initial begin
        // 初始化信号
        cpu_req = 0;
        cpu_we = 0;
        cpu_addr = 0;
        cpu_wdata = 0;

        // 等待复位完成
        @(posedge rst_n);
        #10;

        // 测试1: 连续读（测试命中率）
        $display("===== Test 1: Sequential Read =====");
        for (int i = 0; i < 100; i++) begin
            cpu_access(i * 4, 0, 0); // 地址递增，模拟空间局部性
            total_cycles += 1;
        end

        // 测试2: 随机读写（测试替换策略）
        $display("===== Test 2: Random Access =====");
        for (int i = 0; i < 100; i++) begin
            cpu_access($urandom_range(0, 255) * 4, $urandom_range(0, 1), $urandom());
            total_cycles += 1;
        end

        // 输出统计结果
        $display("\n===== Simulation Results =====");
        $display("Total Accesses: %0d", total_access);
        $display("Hit Count: %0d", hit_count);
        $display("Miss Count: %0d", total_access - hit_count);
        $display("Hit Rate: %.2f%%", (hit_count * 100.0) / total_access);
        $display("Average CPI: %.2f", (total_cycles * 1.0) / total_access);
        $finish;
    end

    // CPU访问任务
    task cpu_access(input [ADDR_WIDTH-1:0] addr, input we, input [DATA_WIDTH-1:0] wdata);
        cpu_req = 1;
        cpu_we = we;
        cpu_addr = addr;
        cpu_wdata = wdata;

        // 等待缓存响应
        @(posedge clk iff cpu_ready);

        // 统计命中/未命中
        total_access += 1;
        if (cpu_hit) hit_count += 1;

        // 打印调试信息
        if (we)
            $display("[%0t] CPU Write: addr=%0h, data=%0h, hit=%0b", $time, addr, wdata, cpu_hit);
        else
            $display("[%0t] CPU Read: addr=%0h, data=%0h, hit=%0b", $time, addr, cpu_rdata, cpu_hit);

        // 结束请求
        cpu_req = 0;
    endtask

endmodule