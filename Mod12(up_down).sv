//****************1.RTL CODE (DUT) *****************//
module counter(clk,rst,load,mode,data_in,data_out);
	input clk,rst,load,mode;
	input [3:0] data_in;
	output reg [3:0] data_out;
	always @(posedge clk)
		begin
		     if(rst)
			data_out <= 4'd0;
			
		     else if(load)
			data_out <= data_in;
			
		     else if(mode)              //Mode-1 --> Up counting, Mode-0 --> Down counting
			begin
			     if(data_out == 4'd11)
				data_out <= 4'd0;
			     else 
				data_out <= data_out + 1'b1;
			end
		     else
			begin
			     if(data_out == 4'd0)
				data_out <= 4'd11;
			     else
				data_out <= data_out - 1'b1;
			end
		end
endmodule			

//************************2. INTERFACE BLOCK ***********************//
interface count_if(input bit clk);
	logic rst;
	logic load;
	logic mode;
	logic [3:0] data_in;
	logic [3:0] data_out;
	
	//clocking block for write driver
	clocking wr_drv_cb @(posedge clk);
		default input #1 output #1;
		output rst;
		output mode;
		output data_in;
		output load;
	endclocking : wr_drv_cb
	
	//clocking block for write monitor
	clocking wr_mon_cb @(posedge clk);
		default input #1 output #1;
		input rst;
		input mode;
		input data_in;
		input load;
	endclocking : wr_mon_cb

	//clocking block for read monitor
	clocking rd_cb @(posedge clk);
		default input #1 output #1;
		input data_out;
	endclocking : rd_cb

	//Modports
	//Write Driver Modport
	modport WR_DRV(clocking wr_drv_cb);

	//Write monitor modport
	modport WR_MON(clocking wr_mon_cb);

	//Read monitor modport
	modport RD_MON(clocking rd_cb);
endinterface : count_if

//****************************3. SVTB *******************************//
/* TB components are 1. Transaction,
		     2. Generator,
		     3. Write Driver,
		     4. Write Monitor,
		     5. Read Monitor,
		     6. Reference Model,
		     7. Score Board 
		     8. Environment,
		     9. Test Class.
		    10. Top Module */
//******************************************************************//

//****************************1. Transaction ***********************//
class count_trans;
	rand bit [3:0] data_in;
	rand bit rst;
	rand bit load;
	rand bit mode;
	
	logic [3:0] data_out;

	constraint C1 {rst dist{0 := 90, 1 := 10};}
	constraint C2 {load dist{0 := 30, 1 := 30};}
	constraint C3 {mode dist{0 := 50, 1 := 50};}
	constraint C4 {data_in inside {[0:11]};}

	static int up_count;
	static int down_count;
	static int no_of_data_in;
	int no_of_transactions = 5;
	
	function void display(input string message);
		$display("------------------------------------");
		$display("\nInput String message: %s",message);
		$display("\n No_of_data = %0d",no_of_data_in);
		$display("\n Up_count = %0d",up_count);
		$display("\n Down_count = %0d",down_count);
		$display($time,"rst = %d\tload = %d\tmode = %d\tdata_in = %d\tdata_out = %d",rst,load,mode,data_in,data_out);
		$display("------------------------------------");
	endfunction : display
	
	function void post_randomize();
		if(this.rst == 0 && this.load == 1)
			no_of_data_in++;
		if(this.rst == 0 && this.mode == 1 && this.load == 0)
			up_count++;
		if(this.rst == 0 && this.mode == 0 && this.load == 0)
			down_count++;
		this.display("Randomized Data");
	endfunction : post_randomize
endclass : count_trans

//****************************2. GENERATOR ****************************//
class count_gen;
	count_trans gen_trans;
	count_trans data2send;

	//generator to write driver mailbox
	mailbox #(count_trans) gen2wr;

	//overriding mapping method static address to Dynamic address
	function new(mailbox #(count_trans) gen2wr);
		this.gen2wr = gen2wr;
		gen_trans = new;
	endfunction : new

	virtual task start();
		fork
		    begin
			for(int i=0; i<gen_trans.no_of_transactions;i++)
				begin
					assert(gen_trans.randomize());
					data2send = new gen_trans;   //Shallow copy
					gen2wr.put(data2send);
				end
		    end
		join_none
	endtask : start
endclass : count_gen

//*******************************3. WRITE DRIVER ***************************//
class count_wr_drv;
	
	//virtual local interface handle
	virtual count_if.WR_DRV wr_drv_if;

	//counter transaction handle
	count_trans data2duv;

	//generator to write driver mailbox
	mailbox #(count_trans) gen2wr;
	
	//overriding method
	function new(virtual count_if.WR_DRV wr_drv_if,
			mailbox #(count_trans) gen2wr);
		this.wr_drv_if = wr_drv_if;
		this.gen2wr = gen2wr;
	endfunction : new

	virtual task drive();
		@(wr_drv_if.wr_drv_cb);
		begin
			wr_drv_if.wr_drv_cb.rst <= data2duv.rst;
			wr_drv_if.wr_drv_cb.load <= data2duv.load;
			wr_drv_if.wr_drv_cb.mode <= data2duv.mode;
			wr_drv_if.wr_drv_cb.data_in <= data2duv.data_in;
		end
	endtask : drive

	virtual task start();
		fork
		    begin
			forever
				begin
					gen2wr.get(data2duv);
					drive();
				end
		    end
		join_none
	endtask : start
endclass : count_wr_drv

//*********************************4. WRITE MONITOR *************************//
class count_wr_mon;
	
	//virtual local interface handle
	virtual count_if.WR_MON wr_mon_if;
	
	//read monitor to reference model handle
	count_trans data2rm;
	
	//for shallow copy 
	count_trans wr_data; 

	//write monitor to reference model 1 mailbox
	mailbox #(count_trans) mon2rm;

	//overriding method
	function new(virtual count_if.WR_MON wr_mon_if,
			mailbox #(count_trans) mon2rm);
		this.wr_mon_if = wr_mon_if;
		this.mon2rm = mon2rm;
		wr_data = new;
	endfunction : new		
	
	//task monitor
	virtual task monitor();
		@(wr_mon_if.wr_mon_cb);
		//wait(wr_mon_if.wr_mon_cb.rst == 1);
		//@(wr_mon_if.wr_mon_cb);
		begin
			wr_data.rst = wr_mon_if.wr_mon_cb.rst;
			wr_data.load = wr_mon_if.wr_mon_cb.load;
			wr_data.mode = wr_mon_if.wr_mon_cb.mode;
			wr_data.data_in = wr_mon_if.wr_mon_cb.data_in;
			$display("\n Write monitor %p",wr_data);
		end
	endtask : monitor

	virtual task start();
		fork
		    begin
			forever
				begin
					monitor();
					data2rm = new wr_data;
					mon2rm.put(data2rm);
				end
		    end
		join_none
	endtask : start
endclass : count_wr_mon

//****************************5. READ MONITOR ***************************//	
class count_rd_mon;
	
	//virtual interface handle
	virtual count_if.RD_MON rd_mon_if;
	
	//two transaction handles
	count_trans data2sm;
	count_trans rd_data;
		
	//one mailbox
	mailbox #(count_trans) rm2sb;

	//overriding method
	function new(virtual count_if.RD_MON rd_mon_if,
			mailbox #(count_trans) rm2sb);
		this.rd_mon_if = rd_mon_if;
		this.rm2sb = rm2sb;
		rd_data = new;
	endfunction : new

	virtual task monitor();
		@(rd_mon_if.rd_cb);
		begin
			rd_data.data_out = rd_mon_if.rd_cb.data_out;
			//rd_data.display("\n Data from Read monitor");
			$display("\n Read monitor %p",rd_data);
		end
	endtask : monitor
	
	virtual task start();
		fork
		    begin
			forever
				begin
					monitor();
					data2sm = new rd_data;
					rm2sb.put(data2sm);  //received by scoreboard
				end
		    end
		join_none
	endtask : start
endclass : count_rd_mon

//*******************************6. REFERENCE MODEL***********************//
class count_model;
	
	//one transaction handle
	count_trans mon2sb;

	//reference has 2 mailboxes
	mailbox #(count_trans) mon2rm;
	mailbox #(count_trans) rf2sb;

	static logic [3:0] ref_count = 0;

	//overriding
	function new(mailbox #(count_trans) mon2rm,
			mailbox #(count_trans) rf2sb);
		this.mon2rm = mon2rm;
		this.rf2sb = rf2sb;
	endfunction : new

	//checking to the expected values
	virtual task count_mod(count_trans w_data);
		begin
			if(w_data.rst)
				ref_count <= 4'd0;
			else if(w_data.load)
				ref_count <= w_data.data_in;
			else
				wait(w_data.load == 0)
				begin
					if(w_data.mode)
						ref_count <= (ref_count >= 4'd11) ? 4'd0 : ref_count+1;
					else
						ref_count <= (ref_count == 4'd0) ? 4'd11 : ref_count-1;
				end
		end
	endtask : count_mod

	virtual task start();
		fork 
		    begin
			//fork 
			    //begin
				forever
					begin
						mon2rm.get(mon2sb);
						count_mod(mon2sb);
						mon2sb.data_out = ref_count;
						$display("\n reference model values %p",mon2sb);
						rf2sb.put(mon2sb);
					end
			    //end
			//join
		    end
		join_none
	endtask : start
endclass : count_model
					
//****************************7. SCORE BOARD ******************************//	
class count_sb;
	
	//event done;
	event DONE;
	
	static int ref_data,r_data,data_verified;

	count_trans rmd_data;
	count_trans sb_data;
	count_trans cov_data;

	//mailboxes from ref model to sb and rdmon to sb
	mailbox #(count_trans) rf2sb;
	mailbox #(count_trans) rm2sb;

	//define code coverage
	covergroup counter_cov;
		option.per_instance = 1;
		RST  : coverpoint cov_data.rst{
						bins low = {0};
						bins high = {1};}
		LOAD : coverpoint cov_data.load;
		MODE : coverpoint cov_data.mode;
		DATA : coverpoint cov_data.data_in{bins a = {[1:10]};}
		CR   : cross RST,LOAD,MODE,DATA;
	endgroup : counter_cov

	function new(mailbox #(count_trans) rf2sb,
			mailbox #(count_trans) rm2sb);
		this.rf2sb = rf2sb;
		this.rm2sb = rm2sb;
		counter_cov = new;
	endfunction : new

	virtual task start();
		fork
		    forever
			begin
				rf2sb.get(rmd_data);
				ref_data++;
				rm2sb.get(sb_data);
				r_data++;
				$display("\n In Score Board \n Reference values %p \n Read monitor values %p",rmd_data,sb_data);
				check(sb_data);
			end
		join_none
	endtask : start	


	virtual task check(count_trans rdata);
		if(rmd_data.data_out == rdata.data_out)
			begin
				$display("\n data_out matches");
				cov_data = rmd_data;
				counter_cov.sample();
			end
		else
			$display("\n data_out not matching");
		data_verified++;
		
		if(data_verified >= rmd_data.no_of_transactions)
			begin
				-> DONE;
			end
	endtask : check

	
	function void report;
		$display("\n ---------------SCOREBOARD REPORT----------------");
		$display("\n Data generated : %p",rmd_data);
		$display("\n Data received : %p",sb_data);
		$display("\n Data Verified : %d",data_verified);
		$display("\n --------------SCOREBOARD REPORT----------------");
	endfunction : report
endclass : count_sb

//***************************8. ENVIRONMENT********************************//
class env;
	
	//3local virtual interface handles
	virtual count_if.WR_DRV wr_drv_if;
	virtual count_if.WR_MON wr_mon_if;
	virtual count_if.RD_MON rd_mon_if;
		
	//according to the architecture 4 mailboxex created
	mailbox #(count_trans) gen2wr = new;
	mailbox #(count_trans) rf2sb = new;
	mailbox #(count_trans) wmon2rm = new;
	mailbox #(count_trans) rmon2sb = new;
		
	//create tb components handles using build
	count_gen           gen_h;
	count_wr_drv        dri_h;
	count_wr_mon        wrmon_h;
	count_rd_mon        rdmon_h;
	count_model         mod_h;
	count_sb            sb_h;
		
	//overriding method
	function new(virtual count_if.WR_DRV wr_drv_if,
			virtual count_if.WR_MON wr_mon_if,
			virtual count_if.RD_MON rd_mon_if);
		this.wr_drv_if = wr_drv_if;
		this.wr_mon_if = wr_mon_if;
		this.rd_mon_if = rd_mon_if;
	endfunction : new

	virtual task build();
		gen_h = new(gen2wr);
		dri_h = new(wr_drv_if,gen2wr);
		wrmon_h = new(wr_mon_if,wmon2rm);
		rdmon_h = new(rd_mon_if,rmon2sb);
		mod_h = new(wmon2rm,rf2sb);
		sb_h = new(rf2sb,rmon2sb);
	endtask : build
		
	virtual task reset_duv();
		@(wr_drv_if.wr_drv_cb);
		wr_drv_if.wr_drv_cb.rst <= 1'b1;
		//@(wr_drv_if.wr_drv_cb);
	endtask : reset_duv

	virtual task start();
		gen_h.start();
		dri_h.start();
		wrmon_h.start();
		rdmon_h.start();
		mod_h.start();
		sb_h.start();
	endtask : start
		
	//triggering event
	task stop();
		wait(sb_h.DONE.triggered);
	endtask : stop
	
	virtual task run();
		reset_duv();
		start();
		stop();
		sb_h.report();
	endtask : run
endclass : env

//************************9. TEST************************//
class test;
	
	//3 virtual local interfaces handles
	virtual count_if.WR_DRV wr_drv_if;
	virtual count_if.WR_MON wr_mon_if;
	virtual count_if.RD_MON rd_mon_if;

	//Declare an handle for counter_env as env_h
	env env_h;
	//overriding
	function new(virtual count_if.WR_DRV wr_drv_if,
			virtual count_if.WR_MON wr_mon_if,
			virtual count_if.RD_MON rd_mon_if);
		this.wr_drv_if = wr_drv_if;
		this.wr_mon_if = wr_mon_if;
		this.rd_mon_if = rd_mon_if;
		env_h = new(wr_drv_if,wr_mon_if,rd_mon_if);
	endfunction : new

	virtual task build_and_run();
		env_h.build();
		env_h.run();
		$finish;
	endtask : build_and_run
endclass : test

//******************************10. TOP MODULE**********************//
module top;
	parameter cycle = 10;
	bit clk;
	
	count_if DUV_IF (clk);
	test t_h;
	counter MOD12(.clk(clk),
			.rst(DUV_IF.rst),
			.mode(DUV_IF.mode),
			.load(DUV_IF.load),
			.data_in(DUV_IF.data_in),
			.data_out(DUV_IF.data_out));
	initial 
		begin
			t_h = new(DUV_IF,DUV_IF,DUV_IF);
			t_h.build_and_run();
		end
	initial
		begin
			clk = 1'b0;
			forever #(cycle/2) clk = ~clk;
		end
endmodule : top



