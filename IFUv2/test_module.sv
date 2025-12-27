`timescale 1ns / 1ps

module test_module(
    input  logic clk,
    input  logic rst_n
);

    // --- 1. Internal Constants & Handshakes ---
    // Tied high for synthesis so the fetch unit runs continuously
    logic        dec_read_en = 1'b1; 
    
    // Core Decoder Signals
    logic [31:0] dec_instr;
    logic [31:0] dec_pc;
    logic        dec_valid;

    // --- 2. Ground Truth (Oracle) Interface ---
    logic        actual_is_branch;
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        feedback_valid;
    logic        branch_resolved;

    // --- 3. Memory & DPFU Interconnects ---
    logic [31:0]  w_addr;
    logic         w_req;
    logic [127:0] w_data;
    logic         w_valid;
    logic         w_done;
    logic [2:0]   w_ins_count,ins_count; 
    assign w_data=0;
    logic[3:0]  temp =3'b0;
    // --- 4. Instantiate Oracle (Ground Truth) ---
    // Synthesizes into Block RAM using target_values.mem
    bpu_ground_truth_feedback oracle (
        .clk              (clk),
        .rst_n            (rst_n),
        .bpu_fetch_pc     (dec_pc), 
        .bpu_valid        (dec_valid),
        .actual_is_branch (actual_is_branch),
        .actual_taken     (branch_taken),
        .actual_target_pc (branch_target),
        .feedback_valid   (feedback_valid)
    );

    assign branch_resolved = feedback_valid && actual_is_branch;

    // --- 5. Instantiate DPFU_top (Main Design) ---
    DPFU_top dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .ins_count(ins_count),
        .branch_resolved (branch_resolved),
        .branch_taken    (branch_taken),
        .branch_pc       (dec_pc),        
        .branch_target   (branch_target),
        .dec_read_en     (dec_read_en),
        .dec_instr       (dec_instr),
        .dec_pc          (dec_pc),
        .dec_valid       (dec_valid)
    );
ila_0 ila (
         .clk(clk), 
 
         .probe0(rst_n),             // wire [0:0]
         .probe1(clk),           // wire [0:0]
         .probe2(dec_instr),         // wire [31:0]
         .probe3(dec_pc),            // wire [31:0]
         .probe4(dec_pc),            // wire [31:0]
         .probe5(branch_target),           // wire [31:0] - Now using local wire
         .probe6(w_data),            // wire [127:0]
         .probe7(w_data),     // wire [127:0] - Now using local wire
         .probe8(ins_count),         // wire [2:0]
         .probe9(ins_count),              // wire [2:0]
         .probe10(temp),   // wire [3:0] - Now using local wire
         .probe11(dec_valid),        // wire [0:0]
         .probe12(clk),        // wire [0:0] - Now using local wire
         .probe13(branch_resolved),  // wire [0:0]
         .probe14(branch_taken),     // wire [0:0]
         .probe15(dec_read_en)            // wire [0:0]
     );

endmodule