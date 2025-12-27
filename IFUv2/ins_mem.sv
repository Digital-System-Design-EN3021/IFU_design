`timescale 1ns / 1ps

module I_mem(
    input  logic clk,
    input  logic reset,
    
    // --- Request Interface (from DPFU Control) ---
    input  logic [31:0]    cache_addr_in,      // Address of the instruction block (PC)
    input  logic           cache_request_in,   // DPFU asserts this when fetching
    input  logic [2:0]     ins_count,
    
    // --- Response Interface (to DPFU Control) ---
    output logic [127:0]   cache_rdata_out,    // 128-bit burst of 4 instructions
    output logic           cache_rvalid_out,   // Asserts high when rdata_out is valid
    output logic           cache_burst_done,   // Indicates all bursts complete
    output logic [3:0] remaining
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
        if (~reset) begin
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
                        current_base     <= cache_addr_in[8:2];
                        total_ins_count  <= ins_count;
                        
                        ins_fetched <= '0;
                        req_state       <= BURST;
                    end
                end
                
                BURST: begin
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
//                    if (ins_fetched + current_burst_size >= total_ins_count) begin
//                        // All instructions fetched
//                        cache_burst_done <= 1'b1;
//                        req_state        <= IDLE;
//                    end
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
            instruction_memory[k] = 32'h00000000 + k ;
        end
    end
endmodule


