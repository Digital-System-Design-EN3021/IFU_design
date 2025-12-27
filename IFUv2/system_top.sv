`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/26/2025 02:11:56 PM
// Design Name: 
// Module Name: system_top
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


module system_top(
    input  logic clk,
    input  logic rst_n              // Mispredict from EX stage
    
    // Branch Predictor Interface
    
);      logic [31:0] bpu_next_pc;   // Target from BPU
        logic        bpu_pred_valid;// High if BPU wants to jump
        logic flush   ;
        // Decoder Interface (The Consumer)
        logic        dec_read_en;   // Decoder ready for next instr
        logic [31:0] dec_instr;     // 32-bit instruction to Decoder
        logic [31:0] dec_pc;        // PC of the instruction
        logic        dec_valid;      // High if data is ready for Decoder
        logic [127:0] burst;
        logic [127:0] storetest;
        logic       f_write_en;
        logic [3:0] remaining;
        logic [2:0]   w_mem_ins_count_req;
        // Debug Status
        logic [3:0]  fifo_occupancy;
    logic [127:0] f_write_data;
    logic [31:0]  f_write_pc;
    logic [2:0]   f_ins_count;

    // Internal Signal Interconnects
    logic [31:0]  w_mem_addr;
    logic         w_mem_req;
    
    logic [127:0] w_mem_data;
    logic [2:0]   w_mem_ins_resp;
    logic         w_mem_valid;
    logic         w_mem_done;
    
    logic         w_fifo_full;
    assign flush=1'b0;
    assign w_mem_ins_resp=3'b0;
    assign burst =f_write_data;
    // --- 1. Instruction Memory ---
    I_mem instr_mem_inst (
        .clk              (clk),
        .reset            (!rst_n),
        .cache_addr_in    (w_mem_addr),
        .cache_request_in (w_mem_req),
        .ins_count        (w_mem_ins_count_req),
        .cache_rdata_out  (w_mem_data),
        .cache_rvalid_out (w_mem_valid),
        .cache_burst_done (w_mem_done),
        .remaining(remaining)
    );

    // --- 2. Fetch Controller ---
    fetch_controller controller_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush),
        .next_pc_predicted (bpu_next_pc),
        .prediction_valid  (bpu_pred_valid),
        .mem_addr          (w_mem_addr),
        .mem_req           (w_mem_req),
        .mem_ins_count     (w_mem_ins_count_req),
        .mem_data_in       (w_mem_data),
        // Note: Connecting constant 4 if I_mem doesn't output dynamic count yet
        .mem_ins_count_resp(3'd4), 
        .mem_valid_in      (w_mem_valid),
        .mem_done_in       (w_mem_done),
        .fifo_full         (w_fifo_full),
        .fifo_count        (fifo_occupancy),
        .fifo_write_en     (f_write_en),
        .fifo_write_data   (f_write_data),
        .fifo_write_pc     (f_write_pc),
        .fifo_ins_count    (f_ins_count)
    );

    // --- 3. Prefetch FIFO Buffer ---


    fifo #(.DEPTH(8)) fifo_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (flush),
        .write_enable (f_write_en),
        .write_data   (f_write_data),
        .write_pc     (f_write_pc),
        .ins_count    (f_ins_count),
        .read_enable  (dec_read_en),
        .read_data    (dec_instr),
        .read_pc      (dec_pc),
        .valid        (dec_valid),
        .full         (w_fifo_full),
        .count        (fifo_occupancy),
        .storetest(storetest)
    );
    
    
//ila_0 your_instance_name (
//        .clk(clk), // Use your system clock
    
//        // 32-bit Probes (0-3)
//        .probe0(dec_instr),          // [31:0] Current instruction going to Decoder
//        .probe1(dec_pc),             // [31:0] Current PC going to Decoder
//        .probe2(w_mem_addr),         // [31:0] PC Address being requested from I_mem
//        .probe3(f_write_pc),         // [31:0] Base PC of the burst being written to FIFO
    
//        // 128-bit Probes (4-5) - Crucial for Burst Inspection
//        .probe4(w_mem_data),         // [127:0] Raw data coming from I_mem
//        .probe5(storetest),          // [127:0] Data currently indexed in FIFO
    
//        // Multi-bit Status Probes (6-8)
//        .probe6(w_mem_ins_resp),      // [2:0] How many instructions memory actually returned
//        .probe7(fifo_occupancy),     // [3:0] Current depth of the FIFO
//        .probe8(f_ins_count),        // [2:0] Instruction count for the FIFO write
    
//        // Single-bit Control/Handshake Probes (9-13)
//        .probe9(w_mem_req),          // [0:0] Is the controller asking memory for data?
//        .probe10(w_mem_valid),       // [0:0] Is the memory responding?
//        .probe11(f_write_en),        // [0:0] Is the FIFO actually capturing the burst?
//        .probe12(dec_valid),         // [0:0] Is the FIFO telling the decoder data is ready?
//        .probe13(flush)              // [0:0] Monitor for mispredict flushes
//    );

    
    
    
    

endmodule
