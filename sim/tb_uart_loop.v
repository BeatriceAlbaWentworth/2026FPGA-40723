// ============================================================
//  tb_uart_loop.v  —— 回环自测
//
//  做的事：发 8 个字节进去，看能不能原样收回来。
//  8 个字节正好覆盖 0x00 / 0xFF / 中间值 / 协议里的 0xAA 0x55。
// ============================================================
`timescale 1ns / 1ps

module tb_uart_loop;

    localparam integer CLKS = 54;          // 每位 54 个时钟

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    reg  rx_line = 1'b1;

    wire tx_line;
    wire led;

    // 50 MHz
    always #10 clk = ~clk;

    // ---------------- DUT ----------------
    top_uart_loop #(.CLKS_PER_BIT(CLKS)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .uart_rx_pin (rx_line),
        .uart_tx_pin (tx_line),
        .led         (led)
    );

    // ---------------- 监视器：把 tx 解回字节 ----------------
    wire [7:0] mon_data;
    wire       mon_valid;

    uart_rx #(.CLKS_PER_BIT(CLKS)) mon (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (tx_line),
        .data  (mon_data),
        .valid (mon_valid)
    );

    // ---------------- 发送一个字节 ----------------
    task send_byte(input [7:0] b);
        integer i;
        begin
            rx_line = 1'b0;                        // 起始位
            repeat (CLKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin    // 数据位，LSB 先
                rx_line = b[i];
                repeat (CLKS) @(posedge clk);
            end
            rx_line = 1'b1;                        // 停止位
            repeat (CLKS) @(posedge clk);
        end
    endtask

    // ---------------- 收集回环结果 ----------------
    reg [7:0] got [0:7];
    integer   n;

    always @(posedge clk) begin
        if (mon_valid && n < 8) begin
            got[n] = mon_data;
            $display("  收到第 %0d 个字节: 0x%02X", n, mon_data);
            n = n + 1;
        end
    end

    // ---------------- 主流程 ----------------
    reg [7:0] send_list [0:7];
    integer   i;

    initial begin
        send_list[0] = 8'hAA;
        send_list[1] = 8'h55;
        send_list[2] = 8'h00;
        send_list[3] = 8'hFF;
        send_list[4] = 8'h10;
        send_list[5] = 8'h7E;
        send_list[6] = 8'h81;
        send_list[7] = 8'h5A;

        n = 0;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("---- 开始发送 8 个字节 ----");
        for (i = 0; i < 8; i = i + 1) begin
            $display("  发送第 %0d 个字节: 0x%02X", i, send_list[i]);
            send_byte(send_list[i]);
        end

        // 等回环把 FIFO 排空
        repeat (CLKS * 20) @(posedge clk);

        $display("---- 比对 ----");
        if (n != 8) begin
            $display("FAIL: 只收到 %0d 个字节，期望 8 个", n);
        end else begin
            for (i = 0; i < 8; i = i + 1) begin
                if (got[i] !== send_list[i])
                    $display("FAIL: 第 %0d 个不对，期望 0x%02X 实际 0x%02X",
                             i, send_list[i], got[i]);
                else
                    $display("  OK  : 第 %0d 个 0x%02X", i, got[i]);
            end
            $display("PASS: 8 个字节全部原样返回");
        end

        $finish;
    end

    // 超时保护
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
