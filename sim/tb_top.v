// ============================================================
//  tb_top.v  —— 端到端自测
//
//  从串口引脚灌入一帧真实输入（frame_in.hex，2055 字节），
//  把串口输出的字节全部记录到 e2e_out.hex，交给 Python 比对。
//
//  为了仿真快，CLKS_PER_BIT = 2（真机是 54，字节内容不受影响）。
// ============================================================
`timescale 1ns / 1ps

module tb_top;

    localparam integer CLKS   = 16;     // 仿真用，真机 54
                                        // 不能太小：uart_rx 里有两级同步器（2 拍延迟）
    localparam integer NIN    = 2055;
    localparam integer NOUT   = 4134;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    reg  rx_line = 1'b1;
    wire tx_line;
    wire led;

    top_full #(.CLKS_PER_BIT(CLKS)) dut (
        .clk(clk), .rst_n(rst_n),
        .uart_rx_pin(rx_line),
        .uart_tx_pin(tx_line),
        .led(led)
    );

    // 监视输出
    wire [7:0] mon_byte;
    wire       mon_v;

    uart_rx #(.CLKS_PER_BIT(CLKS)) mon (
        .clk(clk), .rst_n(rst_n), .rx(tx_line),
        .data(mon_byte), .valid(mon_v)
    );

    integer fd, got = 0;

    // 探针：看解帧模块到底吐出了多少样本
    integer nsmp = 0;
    always @(posedge clk) if (dut.smp_v) nsmp = nsmp + 1;

    always @(posedge clk) begin
        if (mon_v) begin
            $fwrite(fd, "%02x\n", mon_byte);
            got = got + 1;
        end
    end

    // 发送一个字节
    task send_byte(input [7:0] b);
        integer i;
        begin
            rx_line = 1'b0;
            repeat (CLKS) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_line = b[i];
                repeat (CLKS) @(posedge clk);
            end
            rx_line = 1'b1;
            repeat (CLKS) @(posedge clk);
        end
    endtask

    reg [7:0] fin [0:NIN-1];
    integer i;

    initial begin
        fd = $fopen("D:/zynq_vibration/proj/vib_pl/src/e2e_out.hex", "w");
        $readmemh("D:/zynq_vibration/proj/vib_pl/src/frame_in.hex", fin);

        repeat (20) @(negedge clk);
        rst_n = 1'b1;
        repeat (20) @(negedge clk);

        $display("---- sending %0d input bytes ----", NIN);
        for (i = 0; i < NIN; i = i + 1)
            send_byte(fin[i]);

        $display("---- waiting for output ----");
        repeat (NOUT * CLKS * 11 + 20000) @(negedge clk);

        $display("  samples parsed : %0d  (expect 1024)", nsmp);
        $display("  bytes received : %0d  (expect %0d)", got, NOUT);
        if (got >= NOUT) $display("DONE");
        else             $display("SHORT: not enough output");

        $fclose(fd);
        $finish;
    end

    initial begin
        #60_000_000;          // 整个流程约 21.5 ms，留足余量
        $display("TIMEOUT");
        $fclose(fd);
        $finish;
    end

endmodule
