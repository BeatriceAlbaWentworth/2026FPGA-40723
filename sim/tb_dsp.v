// ============================================================
//  tb_dsp.v  —— FIR + FFT 联调自测
//
//  输入：sine125.hex（1024 点、125 Hz、幅值 9000 的正弦）
//  期望：FFT 峰值落在 bin 64（125 / 1.953125 = 64）
//       峰值幅度 ≈ 9000 × 512 = 4,608,000
//
//  这个测试台等价于 B 的黄金模型：同一份输入，同样的期望结果。
// ============================================================
`timescale 1ns / 1ps

module tb_dsp;

    localparam integer N = 1024;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;          // 50 MHz

    // ---------------- DUT 端口 ----------------
    reg  [15:0] rom [0:N-1];

    reg         s_tvalid;
    reg  [15:0] s_tdata;
    reg         s_tlast;
    wire        s_tready;

    reg         m_tready = 1'b1;
    wire        m_tvalid;
    wire [63:0] m_tdata;
    wire        m_tlast;

    top_dsp dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .s_tvalid (s_tvalid),
        .s_tdata  (s_tdata),
        .s_tlast  (s_tlast),
        .s_tready (s_tready),
        .m_tready (m_tready),
        .m_tvalid (m_tvalid),
        .m_tdata  (m_tdata),
        .m_tlast  (m_tlast)
    );

    // ---------------- 抓 FFT 输出 ----------------
    integer cap_re [0:N-1];
    integer cap_im [0:N-1];
    integer beat = 0;

    always @(posedge clk) begin
        if (m_tvalid && m_tready && beat < N) begin
            cap_re[beat] = $signed(m_tdata[31:0]);
            cap_im[beat] = $signed(m_tdata[63:32]);
            beat = beat + 1;
        end
    end

    // ---------------- 送一个样本 ----------------
    task send_one(input [15:0] v, input last);
        begin
            s_tvalid = 1'b1;
            s_tdata  = v;
            s_tlast  = last;
            @(posedge clk);
            while (!s_tready) @(posedge clk);
            s_tvalid = 1'b0;
            s_tlast  = 1'b0;
        end
    endtask

    // ---------------- 主流程 ----------------
    integer n, k, best_bin, best_mag, cur, amp, re, im;

    initial begin
        $readmemh("D:/zynq_vibration/proj/vib_pl/src/sine125.hex", rom);

        s_tvalid = 1'b0;
        s_tdata  = 16'd0;
        s_tlast  = 1'b0;

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("---- 送入 1024 个样本 ----");
        for (n = 0; n < N; n = n + 1)
            send_one(rom[n], (n == N-1));

        $display("---- 等待 FFT 输出 ----");
        while (beat < N) @(posedge clk);
        repeat (50) @(posedge clk);

        $display("---- 找峰值（跳过 bin 0 直流）----");
        best_bin = 0;
        best_mag = -1;
        for (k = 1; k <= 512; k = k + 1) begin
            re  = cap_re[k];
            im  = cap_im[k];
            cur = ((re < 0) ? -re : re) + ((im < 0) ? -im : im);
            if (cur > best_mag) begin
                best_mag = cur;
                best_bin = k;
            end
        end

        amp = best_mag / 512;

        $display("  抓到的输出点数   : %0d", beat);
        $display("  峰值 bin         : %0d   (期望 64)", best_bin);
        $display("  峰值 |I|+|Q|     : %0d   (期望约 4608000)", best_mag);
        $display("  幅值还原 /512    : %0d   (期望约 9000)", amp);
        $display("  bin 64 的 I/Q    : %0d / %0d", cap_re[64], cap_im[64]);

        if (best_bin == 64)
            $display("PASS: 峰值落在 bin 64");
        else
            $display("FAIL: 峰值在 bin %0d，期望 64", best_bin);

        $finish;
    end

    initial begin
        #20_000_000;
        $display("TIMEOUT: 仿真超时");
        $finish;
    end

endmodule
