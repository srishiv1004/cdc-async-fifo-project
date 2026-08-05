module gray_ptr_sync #(
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  src_clk,
    input  logic                  src_rst_n,
    input  logic                  src_en,

    input  logic                  dst_clk,
    input  logic                  dst_rst_n,

    output logic [ADDR_WIDTH:0]   src_gray,
    output logic [ADDR_WIDTH:0]   dst_gray_sync2
);

    logic [ADDR_WIDTH:0] src_bin, src_bin_next, src_gray_next;
    logic [ADDR_WIDTH:0] dst_gray_sync1;

    assign src_bin_next  = src_bin + (ADDR_WIDTH+1)'(src_en);
    assign src_gray_next = (src_bin_next >> 1) ^ src_bin_next;

    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_bin  <= '0;
            src_gray <= '0;
        end else begin
            src_bin  <= src_bin_next;
            src_gray <= src_gray_next;
        end
    end

    // The signal actually wired into the synchronizer's first stage.
    // Correct: gray-coded pointer.
    logic [ADDR_WIDTH:0] src_sync_in;
    assign src_sync_in = src_bin;  // BUG: syncing BINARY pointer, not gray-coded

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_gray_sync1 <= '0;
            dst_gray_sync2 <= '0;
        end else begin
            dst_gray_sync1 <= src_sync_in;
            dst_gray_sync2 <= dst_gray_sync1;
        end
    end

`ifdef FORMAL

    logic f_src_past_valid, f_dst_past_valid;
    logic f_src_rst_n_prev, f_dst_rst_n_prev;

    initial f_src_past_valid = 1'b0;
    always @(posedge src_clk) f_src_past_valid <= 1'b1;
    always_ff @(posedge src_clk) f_src_rst_n_prev <= src_rst_n;
    initial assume (!src_rst_n);
    always @(posedge src_clk)
        if (f_src_past_valid && f_src_rst_n_prev) assume (src_rst_n);

    initial f_dst_past_valid = 1'b0;
    always @(posedge dst_clk) f_dst_past_valid <= 1'b1;
    always_ff @(posedge dst_clk) f_dst_rst_n_prev <= dst_rst_n;
    initial assume (!dst_rst_n);
    always @(posedge dst_clk)
        if (f_dst_past_valid && f_dst_rst_n_prev) assume (dst_rst_n);

    logic [ADDR_WIDTH:0] f_src_sync_in_prev;
    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) f_src_sync_in_prev <= '0;
        else            f_src_sync_in_prev <= src_sync_in;
    end
    always @(posedge src_clk) if (src_rst_n)
        assert ($onehot0(src_sync_in ^ f_src_sync_in_prev));

    logic [ADDR_WIDTH:0] f_dst_gray_sync1_prev;
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) f_dst_gray_sync1_prev <= '0;
        else            f_dst_gray_sync1_prev <= dst_gray_sync1;
    end
    always @(posedge dst_clk) if (dst_rst_n)
        assert (dst_gray_sync2 == f_dst_gray_sync1_prev);
`endif

endmodule
