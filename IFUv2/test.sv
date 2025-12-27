module bpu_ground_truth_feedback #(
    parameter PROG_DEPTH = 256,
    parameter ADDR_WIDTH = 8   // 2^8 = 256 entries
)(
    input  logic        clk,
    input  logic        rst_n,

    // Interface from BPU
    input  logic [31:0] bpu_fetch_pc,     // Current PC being predicted
    input  logic        bpu_valid,        // High when BPU is making a prediction

    // Feedback to BPU (Ground Truth)
    output logic        actual_is_branch,
    output logic        actual_taken,
    output logic [31:0] actual_target_pc,
    output logic        feedback_valid     // High when feedback is ready (delayed by 1 cycle)
);

    // --- 1. Memory Storage (66 bits wide) ---
    (* ram_style = "block" *) logic [65:0] scoreboard_ram [0:PROG_DEPTH-1];

    initial begin
        $readmemh("target_values.mem", scoreboard_ram);
    end

    // --- 2. Synchronous Lookup ---
    logic [65:0] raw_data;
    logic        pipe_valid;
    logic [31:0] pipe_pc;
    logic [8:0]  ins_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_data   <= '0;
            pipe_valid <= 1'b0;
            pipe_pc    <= '0;
            ins_count  <=0;
        end else begin
            // Latency: Address is provided now, Data out on next cycle
            // We use the PC bits [9:2] as the address index (assuming 4-byte aligned)
            if (actual_is_branch)raw_data   <= scoreboard_ram[ins_count];
            else if (bpu_valid) begin 
            raw_data   <= scoreboard_ram[ins_count];
            pipe_valid <= bpu_valid;
            pipe_pc    <= bpu_fetch_pc;
            ins_count<=ins_count+1'b1;
            end 
        end
    end

    // --- 3. Unpacking and Output Matching ---
    always_comb begin
        // The data is valid if the stored PC matches the PC we requested (Tag Check)
        if (pipe_valid && (raw_data[63:32] == pipe_pc)) begin
            feedback_valid   = 1'b1;
            actual_is_branch = raw_data[65];     // MSB 1
            actual_taken     = raw_data[64];     // MSB 2
            actual_target_pc = raw_data[31:0];   // Last 32 bits
        end else begin
            feedback_valid   = 1'b0;
            actual_is_branch = 1'b0;
            actual_taken     = 1'b0;
            actual_target_pc = 32'h0;
        end
    end

endmodule