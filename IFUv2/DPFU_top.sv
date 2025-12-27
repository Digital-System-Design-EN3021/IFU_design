`timescale 1ns / 1ps

module DPFU_top(
    input  logic clk,
    input  logic rst_n,
    
    
    // External branch resolution signals (Ground Truth/Execute)
    input  logic        branch_resolved,
    input  logic        branch_taken,
    input  logic [31:0] branch_pc,
    input  logic [31:0] branch_target,
    // External Decoder signals (The Consumer)
    input  logic        dec_read_en,
    output logic [31:0] dec_instr,
    output logic [31:0] dec_pc,
    output logic[2:0] ins_count,
    output logic        dec_valid
);

    // --- Internal Signal Interconnects ---
    logic [31:0]  w_addr;
    logic         w_req;
    logic [127:0] w_data;
    logic         w_valid;
    logic         w_done;
    logic         w_flush;
    
    // Debug/Status signals from I_mem
    logic [3:0]   w_remaining;
    

    // --- 1. Instantiate Instruction Memory (Burst 128-bit) ---
    I_mem instr_mem_inst (
        .clk              (clk),
        .reset            (rst_n),           // I_mem uses active-high 'reset'
        
        // Request Interface
        .cache_addr_in    (w_addr),
        .cache_request_in (w_req),
        .ins_count        (ins_count),             // We request a full burst of 4 instructions
        
        // Response Interface
        .cache_rdata_out  (w_data),
        .cache_rvalid_out (w_valid),
        .cache_burst_done (w_done),
        .remaining        (w_remaining)
    );

    // --- 2. Instantiate Decoupled Pre-Fetch Unit (DPFU) ---
    DPFU ifu_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        

        // Interface to Memory (Matching DPFU ports)
        .mem_addr        (w_addr),
        .mem_req         (w_req),
        .mem_rdata       (w_data),
        .mem_rvalid      (w_valid),
        .mem_rdone       (w_done),
        .mem_count        (ins_count),

        // Branch Resolution (Feedback)
        .branch_resolved (branch_resolved),
        .branch_taken    (branch_taken),
        .branch_pc       (dec_pc),
        .branch_target   (branch_target),

        // Decoder Interface
        .dec_read_en     (1'b1),
        .dec_instr       (dec_instr),
        .dec_pc          (dec_pc),
        .dec_valid       (dec_valid)
        
    );

endmodule