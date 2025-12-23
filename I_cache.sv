`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/14/2025 01:49:27 PM
// Design Name: 
// Module Name: I_cache
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


module I_cache(
    input  logic clk,
    input  logic reset,
    
    // --- Request Interface (from DPFU Control) ---
    input  logic [31:0]    cache_addr_in,      // Address of the instruction block (PC)
    input  logic           cache_request_in,   // DPFU asserts this when fetching
    input logic[2:0]  ins_count,
    // --- Response Interface (to DPFU Control) ---
    output logic [127:0]   cache_rdata_out,    // 128-bit burst of 4 instructions
    output logic           cache_rvalid_out    // Asserts high when rdata_out is valid
);

    // --------------------------------------------------
    // 1. PARAMETERS and Definitions
    // --------------------------------------------------
    localparam CACHE_LATENCY      = 3;         // Simulated latency in clock cycles
    localparam INSTR_SIZE         = 32;        // 32-bit instruction width
    localparam MEM_DEPTH          = 128;       // 128 total instruction slots
    localparam MEM_ADDR_BITS      = 7;         // log2(128) = 7 bits
    
    // Internal instruction memory: 128 entries, each 32 bits.
    logic [INSTR_SIZE-1:0] instruction_memory [MEM_DEPTH-1:0]; 
    
    // --------------------------------------------------
    // 2. Internal Registers for State and Latency
    // --------------------------------------------------
    logic [CACHE_LATENCY-1:0] latency_counter; 
    logic [31:0]              requested_pc_reg;  // PC of the instruction that started the fetch

    typedef enum bit [1:0] {
            IDLE,           
            BURST,     
            DONE      
        } cache_req_state_t;
    cache_req_state_t req_state;
        
        
    logic [MEM_ADDR_BITS-1:0] base_index;
    logic [2:0] ins_cnt;
    
    // --------------------------------------------------
    // 4. Sequential Logic (Latency FSM)
    // --------------------------------------------------
    logic [MEM_ADDR_BITS-1:0] index_0, index_1, index_2, index_3;
    always_ff @(posedge clk) begin
        if (reset) begin
            latency_counter  <= '0;
            cache_rvalid_out <= 1'b0;
            requested_pc_reg <= '0;
            req_state    <=   IDLE;
        end 
        unique case (req_state)
            IDLE: begin
                if (cache_request_in) begin
                   base_index <= requested_pc_reg[8:2]; // Use bits [8:2] to address 128 entries (0-127)
                   if (ins_count<3'd4)ins_cnt= ins_count;
                   else ins_cnt = 3'd4;
                   for (integer i=0;i<ins_cnt;i++)begin
                        cache_rdata_out =  instruction_memory[base_index+i];
                   end
                   cache_rvalid_out <= 1'b1;
                   req_state <= BURST;
                end
            end
            
            BURST: begin
                if(ins_count>4)begin 
                    ins_cnt = ins_count-3'd4;
                    for (integer i=0;i<ins_cnt;i++)begin
                        cache_rdata_out<= instruction_memory[base_index+i];
                    end
                end
                else req_state <= IDLE;
            end
        endcase
    end

    assign cache_rdata_out = {
        instruction_memory[index_3], // Highest PC/Instruction (Bit 127:96)
        instruction_memory[index_2], // (Bit 95:64)
        instruction_memory[index_1], // (Bit 63:32)
        instruction_memory[index_0]  // Lowest PC/Instruction (Bit 31:0)
    };

    // --------------------------------------------------
    // 6. Memory Initialization
    // --------------------------------------------------
    
    initial begin
        // Initialize 16 instructions (0-15) for testing
        // This simulates instructions residing in the cache.
        for (integer k = 0; k < MEM_DEPTH; k = k + 4) begin
            instruction_memory[k] = 32'h00000000 + k;
        
        end
    end

endmodule

module I_cachen(
    input  logic clk,
    input  logic reset,
    
    // --- Request Interface (from DPFU Control) ---
    input  logic [31:0]    cache_addr_in,      // Address of the instruction block (PC)
    input  logic           cache_request_in,   // DPFU asserts this when fetching
    input  logic [2:0]     ins_count,
    
    // --- Response Interface (to DPFU Control) ---
    output logic [127:0]   cache_rdata_out,    // 128-bit burst of 4 instructions
    output logic           cache_rvalid_out,   // Asserts high when rdata_out is valid
    output logic           cache_burst_done    // Indicates all bursts complete
);
    // --------------------------------------------------
    // 1. PARAMETERS and Definitions
    // --------------------------------------------------
    localparam CACHE_LATENCY      = 3;         // Simulated latency in clock cycles
    localparam INSTR_SIZE         = 32;        // 32-bit instruction width
    localparam MEM_DEPTH          = 128;       // 128 total instruction slots
    localparam MEM_ADDR_BITS      = 7;         // log2(128) = 7 bits
    
    // Internal instruction memory: 128 entries, each 32 bits.
    logic [INSTR_SIZE-1:0] instruction_memory [MEM_DEPTH-1:0]; 
    
    // --------------------------------------------------
    // 2. Internal Registers for State and Latency
    // --------------------------------------------------
    logic [CACHE_LATENCY-1:0] latency_counter; 
    logic [31:0]              requested_pc_reg;
    logic [2:0]               total_ins_count;  // Total instructions requested
    
    typedef enum bit [1:0] {
        IDLE,           
        LATENCY,        
        BURST,
        WAIT_ACK
    } cache_req_state_t;
    
    cache_req_state_t req_state;
    
    logic [MEM_ADDR_BITS-1:0] base_index;
    logic [3:0] ins_fetched;              // Total instructions fetched so far (up to 8+)
    logic [2:0] current_burst_size;       // Size of current burst (1-4)
    logic [MEM_ADDR_BITS-1:0] current_base;
    
    // --------------------------------------------------
    // 3. Sequential Logic (Multi-Burst FSM)
    // --------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            latency_counter   <= '0;
            cache_rvalid_out  <= 1'b0;
            cache_burst_done  <= 1'b0;
            cache_rdata_out   <= '0;
            requested_pc_reg  <= '0;
            req_state         <= IDLE;
            ins_fetched       <= '0;
            current_burst_size <= '0;
            current_base      <= '0;
            base_index        <= '0;
            total_ins_count   <= '0;
        end 
        else begin
            case (req_state)
                IDLE: begin
                    cache_rvalid_out <= 1'b0;
                    cache_burst_done <= 1'b0;
                    
                    if (cache_request_in) begin
                        // Store request information
                        requested_pc_reg <= cache_addr_in;
                        base_index       <= cache_addr_in[8:2];
                        current_base     <= cache_addr_in[8:2];
                        
                        // Store total instruction count
                        if (ins_count == 3'd0) begin
                            total_ins_count <= 3'd4;  // Default to 4 if 0
                        end else begin
                            total_ins_count <= ins_count;
                        end
                        
                        ins_fetched <= '0;
                        
                        // Start latency counter for first burst
                        latency_counter <= 1;
                        req_state       <= LATENCY;
                    end
                end
                
                LATENCY: begin
                    // Simulate cache latency
                    if (latency_counter == CACHE_LATENCY) begin
                        latency_counter <= '0;
                        req_state       <= BURST;
                    end else begin
                        latency_counter <= latency_counter + 1;
                    end
                end
                
                BURST: begin
                    // Calculate how many instructions in this burst
                    logic [3:0] remaining;
                    remaining = total_ins_count - ins_fetched;
                    
                    if (remaining >= 4) begin
                        current_burst_size = 3'd4;
                    end else begin
                        current_burst_size = remaining[2:0];
                    end
                    
                    // Assert valid signal
                    cache_rvalid_out <= 1'b1;
                    
                    // Build the 128-bit output based on burst size
                    case (current_burst_size)
                        3'd1: begin
                            cache_rdata_out <= {96'h0, instruction_memory[current_base]};
                        end
                        3'd2: begin
                            cache_rdata_out <= {64'h0, 
                                              instruction_memory[current_base + 1],
                                              instruction_memory[current_base]};
                        end
                        3'd3: begin
                            cache_rdata_out <= {32'h0,
                                              instruction_memory[current_base + 2],
                                              instruction_memory[current_base + 1],
                                              instruction_memory[current_base]};
                        end
                        default: begin // 4
                            cache_rdata_out <= {instruction_memory[current_base + 3],
                                              instruction_memory[current_base + 2],
                                              instruction_memory[current_base + 1],
                                              instruction_memory[current_base]};
                        end
                    endcase
                    
                    // Update fetched count and base address
                    ins_fetched  <= ins_fetched + current_burst_size;
                    current_base <= current_base + current_burst_size;
                    
                    req_state <= WAIT_ACK;
                end
                
                WAIT_ACK: begin
                    // Hold valid for one cycle, then check if more bursts needed
                    cache_rvalid_out <= 1'b0;
                    
                    if (ins_fetched >= total_ins_count) begin
                        // All instructions fetched
                        cache_burst_done <= 1'b1;
                        req_state        <= IDLE;
                    end else begin
                        // More instructions needed, go back to BURST
                        // No additional latency for subsequent bursts from same region
                        req_state <= BURST;
                    end
                end
                
                default: begin
                    req_state <= IDLE;
                end
            endcase
        end
    end
    
    // --------------------------------------------------
    // 4. Memory Initialization
    // --------------------------------------------------
    initial begin
        // Initialize instructions for testing
        for (integer k = 0; k < MEM_DEPTH; k = k + 1) begin
            instruction_memory[k] = 32'h00000000 + (k << 2);
        end
    end
endmodule


