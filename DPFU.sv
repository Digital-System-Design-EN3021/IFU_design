`timescale 1ns / 1ps

module FIFO(
    input  logic clk,
    input  logic reset,
    input  logic            rden_in,          // IF Stage requests next instruction
    // --- I-Cache (Write) Interface: 128-bit Burst Load ---
    input  logic [127:0]    wdata_burst_in,   // 128 bits of data (4 instructions)
    input  logic            wren_burst_in,    // Asserted when the 128-bit block arrives
    input  logic            flush_in,         // From EX stage mispredict
    // --- IF Stage (Read) Interface: 32-bit Consumption ---
    output logic [31:0]     rdata_out,        // Output: 32-bit instruction
    output logic            rvalid_out,       // Flag: Instruction available
    output logic [3:0]      fill_level_out,    // Current number of instructions in buffer
    output logic [2:0] writeptr,readptr
);

    // --------------------------------------------------
    // 1. PARAMETERS and Internal Definitions
    // --------------------------------------------------
    
    // Architecture Constants
    localparam INSTR_SIZE         = 32;       // 32-bit instruction width
    localparam DPFU_DEPTH         = 8;        // 8-instruction buffer capacity
    localparam DPFU_ADDR_BITS     = 3;        // log2(8)
    localparam CACHE_BUS_WIDTH    = 128;      // 128-bit data bus
    localparam BURST_SIZE         = 4;        // 128 / 32 = 4 instructions loaded per burst
    
    // Internal Storage (Array of 8 x 32-bit instructions)
    logic [INSTR_SIZE-1:0] fifo_ram [DPFU_DEPTH-1:0];
    
    // Pointers and Depth Counter
    logic [DPFU_ADDR_BITS-1:0] w_ptr, r_ptr; // 3-bit pointers (0-7)
    logic [DPFU_ADDR_BITS:0]   depth_cnt;          // 4-bit counter (0-8)

    // --------------------------------------------------
    // 2. FIFO Status and Control Logic
    // --------------------------------------------------
    
    // FIFO is ready to accept a burst if it has at least 4 empty slots
    localparam MAX_DEPTH = DPFU_DEPTH;
    localparam MIN_SPACE_FOR_BURST = BURST_SIZE;
    
    logic fifo_can_write_burst;
    // Must check against a threshold (e.g., must have 4 or more slots free)
    assign fifo_can_write_burst = (depth_cnt <= MAX_DEPTH - MIN_SPACE_FOR_BURST); 
    logic will_write;
    logic will_read;
    assign readptr =r_ptr;
    assign writeptr = w_ptr;
    // --- Pointer and Depth Updates (Sequential) ---
    always_ff @(posedge clk) begin
        if (reset || flush_in) begin
            // Reset or Misprediction Flush: Clear state
            w_ptr  <= '0;
            r_ptr  <= '0;
            depth_cnt <= '0;
        end else begin
            
            // Determine if read/write is possible this cycle
            will_write = wren_burst_in && fifo_can_write_burst;
            will_read  = rden_in && (depth_cnt > 0);
            
            // 1. Pointer Updates
            if (will_write) w_ptr <= w_ptr + BURST_SIZE; // W-Pointer JUMPS by 4
            if (will_read)  r_ptr <= r_ptr + 1;         // R-Pointer steps by 1
            
            // 2. Depth Counter Updates
//            if (will_write && !will_read) depth_cnt <= depth_cnt + BURST_SIZE;
//            else if (will_read && !will_write) depth_cnt <= depth_cnt - 1;
//            else if (will_write && will_read) depth_cnt <= depth_cnt + (BURST_SIZE - 1);
            // If both happen: +4 from write, -1 from read = net +3
            if (w_ptr<r_ptr) depth_cnt <= r_ptr-w_ptr;
            else depth_cnt <= 4'd8-w_ptr+r_ptr;
            
        end
    end

    // --------------------------------------------------
    // 3. Data Write Logic (Burst Loading)
    // --------------------------------------------------
    always_ff @(posedge clk) begin
        if (wren_burst_in && fifo_can_write_burst) begin
            // Load the 128-bit block into 4 sequential 32-bit entries
            // This is the core of the burst load (written in one cycle)
            fifo_ram[w_ptr]     <= wdata_burst_in[ 31:  0]; // Instr 0
            fifo_ram[w_ptr + 1] <= wdata_burst_in[ 63: 32]; // Instr 1
            fifo_ram[w_ptr + 2] <= wdata_burst_in[ 95: 64]; // Instr 2
            fifo_ram[w_ptr + 3] <= wdata_burst_in[127: 96]; // Instr 3
        end
    end

    // --------------------------------------------------
    // 4. Data Read Logic (Single Instruction Delivery)
    // --------------------------------------------------
    
    // Read Data (Combinational read for single-cycle latency delivery)
    assign rdata_out    = fifo_ram[r_ptr];
    
    // Output Status Signals
    assign rvalid_out   = (depth_cnt > 0);       // Valid when the buffer is not empty
    assign fill_level_out = depth_cnt;           // Current fill level
    
endmodule

module DPFU #(
    localparam CACHE_LATENCY      = 3,       // Assume a 3-cycle I-Cache latency
    localparam LOW_WATER_MARK     = 4)
    (
    input  logic clk,
    input  logic reset,
    
    // --- BPU/Pipeline Inputs ---
    input  logic [31:0]    predicted_pc_in,   // The next address from the BPU
    input  logic           predict_taken_in,    // BPU confirms a branch/jump target
    input  logic                   flush_in,            // Misprediction flush
    input  logic                   pipe_ready_in,       // IF stage is ready to consume (rden)

    // --- Output to IF Stage ---
    output logic [31:0]  instr_out,
    output logic                   instr_valid_out,

    // --- I-Cache Interface ---
    output logic [31:0]    cache_addr_out,      // Address sent to I-Cache
    input  logic [127:0]   cache_rdata_in,
    input  logic           cache_rvalid_in      // I-Cache asserts this after latency
);

    // --------------------------------------------------
    // Internal Signals
    // --------------------------------------------------
    
    // FIFO Interface Signals
    logic [2:0] fifo_fill_level;
    logic fifo_wren; // Write enable to FIFO (from I-Cache)
    
    // PC Management
    logic [31:0] last_requested_pc; // PC of the block currently being fetched
    logic [31:0] next_sequential_pc;
    
    // Request State Machine (SM) - Tracks I-Cache interaction
    typedef enum bit [1:0] {
        IDLE,           // No request pending, waiting for trigger
        WAIT_CACHE,     // Request issued, waiting for cache_rvalid
        BURST_LOAD      // Cache_rvalid asserted, loading data
    } cache_req_state_t;
    cache_req_state_t req_state;

    // --------------------------------------------------
    // 3. DPFU FIFO Instantiation
    // --------------------------------------------------
    FIFO fifo_i (
        .clk(clk),
        .reset(reset),
        
        // Write Interface (Driven by I-Cache)
        .wdata_burst_in(cache_rdata_in),
        .wren_burst_in(fifo_wren),
        
        // Read Interface (To IF Stage)
        .rdata_out(instr_out),
        .rvalid_out(instr_valid_out),
        .rden_in(pipe_ready_in), // Pipe_ready acts as the Read Enable
        
        // Status/Control
        .flush_in(flush_in),
        .fill_level_out(fifo_fill_level)
    );

    // --------------------------------------------------
    // 4. DPFU Control Logic
    // --------------------------------------------------
    assign next_sequential_pc = last_requested_pc + (2 * 4); 

    // Define Prefetch Triggers
    logic trigger_low_water;
    logic trigger_branch;

    // Trigger when the buffer is half-empty or less (proactive prefetch)
    assign trigger_low_water = (fifo_fill_level <= LOW_WATER_MARK) && (req_state == IDLE);
    
    // Trigger when the BPU predicts a jump to a new target (highest priority)
    assign trigger_branch = predict_taken_in; 
    
    // Output the current fetch address (New Target > Low Water > Sequential)
    always_comb begin
        if (trigger_branch) begin
            cache_addr_out = predicted_pc_in;
        end else if (trigger_low_water) begin
            cache_addr_out = next_sequential_pc;
        end else begin
            cache_addr_out = '0; // Idle state, no request address
        end
    end

    // --- Request State Machine (Manages Latency) ---
    always_ff @(posedge clk) begin
        if (reset || flush_in) begin
            req_state <= IDLE;
            fifo_wren <= 1'b0;
            last_requested_pc <= '0;
        end else begin
            fifo_wren <= 1'b0; // Default to no write
            
            unique case (req_state)
                IDLE: begin
                    if (trigger_branch || trigger_low_water) begin
                        req_state <= WAIT_CACHE;
                        last_requested_pc <= cache_addr_out; // Lock the address being fetched
                    end
                end
                
                WAIT_CACHE: begin
                    if (cache_rvalid_in) begin
                        // I-Cache is done waiting; start the burst load immediately
                        req_state <= BURST_LOAD;
                    end
                end
                
                BURST_LOAD: begin
                    fifo_wren <= 1'b1;
                    req_state <= IDLE;
                    
                end
            endcase
        end
    end

endmodule
