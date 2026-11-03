// ============================================================
//  top_dsp.v  —— FIR + FFT 数据通路（不含串口）
//
//  数据流：
//    s_axis(16b 实数) → FIR → 取[30:15] 得 int16 → FFT(实部,虚部=0)
//                     → FFT 输出 64b（[31:0]=实部, [63:32]=虚部）
//
//  位宽来源（读自 IP 配置）：
//    FIR 输入 16 位，输出 32 位（1 符号 + 16 整数 + 15 小数）
//    FFT 输入 16 位实数（装在 32 位复合总线低半部）
//    FFT 输出每分量 27 位，装在 32 位槽里
// ============================================================
`timescale 1ns / 1ps

module top_dsp (
    input  wire        clk,
    input  wire        rst_n,

    // 上游：样本输入
    input  wire        s_tvalid,
    input  wire [15:0] s_tdata,
    input  wire        s_tlast,
    output wire        s_tready,

    // 下游：频谱输出
    input  wire        m_tready,
    output wire        m_tvalid,
    output wire [63:0] m_tdata,
    output wire        m_tlast
);

    // ---------------- FIR ----------------
    wire        fir_s_tready;
    wire        fir_m_tvalid;
    wire        fir_m_tready;
    wire [31:0] fir_m_tdata;
    wire        fir_m_tlast;

    fir_compiler_0 u_fir (
        .aclk                 (clk),
        .aresetn              (rst_n),

        .s_axis_data_tdata    (s_tdata),
        .s_axis_data_tvalid   (s_tvalid),
        .s_axis_data_tready   (fir_s_tready),
        .s_axis_data_tlast    (s_tlast),

        .m_axis_data_tdata    (fir_m_tdata),
        .m_axis_data_tvalid   (fir_m_tvalid),
        .m_axis_data_tready   (fir_m_tready),
        .m_axis_data_tlast    (fir_m_tlast)
    );

    assign s_tready = fir_s_tready;

    // FIR 输出 32 位，小数点在第 15 位 → 取 [30:15] 得到 int16 结果
    wire signed [15:0] fir_out16 = fir_m_tdata[30:15];

    // ---------------- FFT ----------------
    // 输入是复数总线：低 16 位实部，高 16 位虚部（实数输入 → 虚部填 0）
    wire [31:0] fft_s_tdata = {16'h0000, fir_out16};

    wire        fft_s_tready;
    wire        fft_m_tvalid;

    // 配置字：8 位，bit0 = FWD_INV。实数输入下正/反变换的幅度谱相同，
    // 这里填 0，靠复位后单拍脉冲配置一次。
    reg  [2:0]  cfg_cnt;
    reg         cfg_tvalid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_cnt    <= 3'd0;
            cfg_tvalid <= 1'b0;
        end else if (cfg_cnt != 3'd4) begin
            cfg_cnt    <= cfg_cnt + 1'b1;
            cfg_tvalid <= (cfg_cnt == 3'd2);   // 第 3 拍发一次
        end else begin
            cfg_tvalid <= 1'b0;
        end
    end

    xfft_0 u_fft (
        .aclk                        (clk),
        .aresetn                     (rst_n),

        .s_axis_config_tdata         (8'h00),
        .s_axis_config_tvalid        (cfg_tvalid),
        .s_axis_config_tready        (),

        .s_axis_data_tdata           (fft_s_tdata),
        .s_axis_data_tvalid          (fir_m_tvalid),
        .s_axis_data_tready          (fft_s_tready),
        .s_axis_data_tlast           (fir_m_tlast),

        .m_axis_data_tdata           (m_tdata),
        .m_axis_data_tvalid          (m_tvalid),
        .m_axis_data_tready          (m_tready),
        .m_axis_data_tlast           (m_tlast)
    );

    assign fir_m_tready = fft_s_tready;

endmodule
