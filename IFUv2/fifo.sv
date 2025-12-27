`timescale 1ns / 1ps

module fifo #(
    parameter DEPTH = 8  // As per your second snippet
)(
    input  logic clk,
    input  logic rst_n,
    input  logic flush,             // From EX stage mispredict

    // --- Write Interface (from Memory/Cache) ---
    input  logic         write_enable,    // renamed from wren_burst_in
    input  logic [127:0] write_data,      // 128-bit burst (4 instructions)
    input  logic [31:0]  write_pc,        // The PC of the FIRST instruction in burst
    input  logic [2:0]   ins_count,       // How many instructions in this burst (1-4)

    // --- Read Interface (to Fetch/Decode) ---
    input  logic         read_enable,     // Consumer request
    output logic [31:0]  read_data,       // 32-bit instruction out
    output logic [31:0]  read_pc,         // 32-bit PC out
    output logic         valid,           // Data available flag

    // --- Status ---
    output logic         full,
    output logic         empty,
    output logic [3:0]   count  ,          // 4-bit for depth of 8
    
    output logic [127:0] storetest
);

    // --------------------------------------------------
    // 1. Internal Storage
    // --------------------------------------------------
    logic [31:0] fifo_ram_data [DEPTH-1:0];
    logic [31:0] fifo_ram_pc   [DEPTH-1:0];
    
    logic [2:0] w_ptr; // 3-bit for 0-7
    logic [2:0] r_ptr;
    logic [3:0] depth_cnt;

    // --------------------------------------------------
    // 2. Control and Status Logic
    // --------------------------------------------------
    // We are "full" if we don't have enough space for a maximum burst (4)
    assign full  = (depth_cnt >= (DEPTH - 2)); 
    assign empty = (depth_cnt == 0);
    assign count = depth_cnt;
    assign valid = !empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            w_ptr     <= '0;
            r_ptr     <= '0;
            depth_cnt <= '0;
        end else begin
            // Pointer and Depth Tracking
            case ({write_enable && !full, read_enable && !empty})
                2'b10: begin // Write only
                    w_ptr     <= w_ptr + ins_count;
                    depth_cnt <= depth_cnt + ins_count;
                end
                2'b01: begin // Read only
                    r_ptr     <= r_ptr + 1;
                    depth_cnt <= depth_cnt - 1;
                end
                2'b11: begin // Simultaneous Read and Write
                    w_ptr     <= w_ptr + ins_count;
                    r_ptr     <= r_ptr + 1;
                    depth_cnt <= depth_cnt + ins_count - 1;
                end
                default: ; // Do nothing
            endcase
        end
    end

    // --------------------------------------------------
    // 3. Data and PC Tagging (Writing to RAM)
    // --------------------------------------------------
    always_ff @(posedge clk) begin
        if (write_enable && !full) begin
            // Instruction 0 (Always present if write_enable is high)
            fifo_ram_data[w_ptr]     <= write_data[31:0];
            fifo_ram_pc[w_ptr]       <= write_pc;

            // Instruction 1
            if (ins_count >= 2) begin
                fifo_ram_data[w_ptr + 3'd1] <= write_data[63:32];
                fifo_ram_pc[w_ptr + 3'd1]   <= write_pc + 32'd4;
            end
            // Instruction 2
            if (ins_count >= 3) begin
                fifo_ram_data[w_ptr + 3'd2] <= write_data[95:64];
                fifo_ram_pc[w_ptr + 3'd2]   <= write_pc + 32'd8;
            end
            // Instruction 3
            if (ins_count >= 4) begin
                fifo_ram_data[w_ptr + 3'd3] <= write_data[127:96];
                fifo_ram_pc[w_ptr + 3'd3]   <= write_pc + 32'd12;
            end
        end
    end
    
    // Inside your FIFO module
    logic [7:0] slot_hit,valid_mask;         // One bit for each of the 8 slots
    logic       bpu_fifo_hit;     // High if any valid slot matches
    logic [2:0] hit_index;        // The location of the target
    
//    always_comb begin
//        slot_hit = 8'b0;
//        for (int i = 0; i < 8; i++) begin
//            if (fifo_ram_pc[i] == write_pc && valid_mask[i]) begin
//                slot_hit[i] = 1'b1;
//            end
//        end
//    end
    
//    assign bpu_fifo_hit = |slot_hit; // OR-reduction (Is there any hit?)
    
//    // Priority Encoder to find the Index (The "Location")
//    always_comb begin
//        if      (slot_hit[0]) hit_index = 3'd0;
//        else if (slot_hit[1]) hit_index = 3'd1;
//        else if (slot_hit[2]) hit_index = 3'd2;
//        else if (slot_hit[3]) hit_index = 3'd3;
//        else if (slot_hit[4]) hit_index = 3'd4;
//        else if (slot_hit[5]) hit_index = 3'd5;
//        else if (slot_hit[6]) hit_index = 3'd6;
//        else if (slot_hit[7]) hit_index = 3'd7;
//        else                  hit_index = 3'd0;
//    end
    
    
   
assign storetest= {fifo_ram_data[w_ptr + 3'd3],fifo_ram_data[w_ptr + 3'd2],fifo_ram_data[w_ptr + 3'd1],fifo_ram_data[w_ptr]} ;
    // --------------------------------------------------
    // 4. Combinational Read Logic
    // --------------------------------------------------
    assign read_data = fifo_ram_data[r_ptr];
    assign read_pc   = fifo_ram_pc[r_ptr];

endmodule