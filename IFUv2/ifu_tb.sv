`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/26/2025 07:22:21 PM
// Design Name: 
// Module Name: ifu_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ifu_tb;

    
    logic dec_read_en, dec_valid;
    logic [31:0] dec_instr, dec_pc;
    logic [31:0] branch_pc;
    logic [3:0]  fifo_count;
    // Feedback signals from Oracle to DUT
    logic branch_resolved, branch_taken;
    logic [31:0] branch_target;
    logic feedback_valid, actual_is_branch;
    logic [65:0] raw_data;
    logic [8:0]  ins_count;
    logic clk, rst_n;
    
    // --- 1. Clock & Reset ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    assign branch_pc= dut.branch_pc;
    assign raw_data=oracle.raw_data;
    assign ins_count = oracle.ins_count;
    assign fifo_count=dut.ifu_inst.fifo_count;
    // --- 2. Instantiate Oracle (Ground Truth) ---
    bpu_ground_truth_feedback oracle (
        .clk(clk),
        .rst_n(rst_n),
        .bpu_fetch_pc(dec_pc), // Probe the address the DUT is requesting
        .bpu_valid(dec_valid),     // Lookup when DUT requests memory
        .actual_is_branch(actual_is_branch),
        .actual_taken(branch_taken),
        .actual_target_pc(branch_target),
        .feedback_valid(feedback_valid)
    );

    // Resolve branch only if oracle confirms it is a branch
    assign branch_resolved = feedback_valid && actual_is_branch;

    // --- 3. Instantiate Design Under Test (DUT) ---
    DPFU_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .branch_resolved(branch_resolved),
        .branch_taken(branch_taken),
        .branch_pc(dut.w_addr), // The PC currently being resolved
        .branch_target(branch_target),
        .dec_read_en(dec_read_en),
        .dec_instr(dec_instr),
        .dec_pc(dec_pc),
        .dec_valid(dec_valid)
    );

    // --- 4. Stimulus ---
    initial begin
        rst_n = 0; dec_read_en = 0;
        #20 rst_n = 1;
        #20 dec_read_en = 1; // Start consuming instructions
        #2000;
        $display("Test Complete.");
        $finish;
    end

    // --- 5. Monitor ---
    always @(posedge clk) begin
        if (dut.w_flush)
            $display("[%0t] MISPREDICT! Path corrected to Target: %h", $time, branch_target);
        if (dec_valid && dec_read_en)
            $display("[%0t] Out: PC=%h Instr=%h", $time, dec_pc, dec_instr);
    end

endmodule
