$:.unshift(File.join(File.expand_path(File.dirname(__FILE__)), '..', 'lib', 'lab'))

require 'yaml'
require 'vm_controller'
require 'enumerator'
require 'instance'

module Msf

class Plugin::Fog < Msf::Plugin
	class BotCommandDispatcher
		include Msf::Ui::Console::CommandDispatcher
	        include Enumerable
		
		attr_accessor :controller

		def initialize(driver)
			super(driver)

			config = "#{Msf::Config.install_root}/data/fog.yml"

			@controller = nil
			print_line  "\n        _  _                 _ .  "
			print_line  "       ( `   )_            (  _ )_   "
			print_line  "      (    )    `)        (_  _(_ ,)"
			print_line  "    (_   (_ .  _) _)   _	"
			print_line  "                      ( _)       Come on lil doggie."
			print_line  "                      "
			print_line  "Using configuration file: #{config}"

			cmd_ch_fog(config)
			
			@bots = Hash.new
			@ittr = 0
		end 

		def commands
		{
		    "ch_help" => "Halllp!",
		    "ch_fog" => "Initialize fog with configuration file. Usage: ch_fog [config.yml]",
		    "ch_load" => "Load currently running instances from cloud server.",
		    "ch_start" => "Start an instance. Usage: ch_start [instance_name]",
		    "ch_start_n" => "Start n instances. Usage: ch_start [n] [instance_name]",
		    "ch_run" => "Run a command. Usage: ch_run [instance_name] [command]",
		    "ch_run_all" => "Run a command on all. Usage: ch_run_all [command]",
		    "ch_run_group" => "Run a command on group. Usage: ch_run_group [group] [command]",
		    "ch_run_obj" => "Run a registered object command. Usage: ch_run_obj [name] [command]",
		    "ch_history" => "List obj history. Usage: ch_obj_history [name]",
		    "ch_list" => "List loaded instances.",
		    "ch_scp_file" => "Copy a file from local to remote.",
		    "ch_clear" => "Clear the current instances set.",
		    "ch_rename" => "Rename an instance attribute, useful if importing running instances.ch_rename [from] [to]",
		    "ch_stop" => "Stop a process on an object. Usage: ch_stop [name] [process]",
		    "ch_set_obj" => "Set an object type. Usage: ch_set [name] [type]",
		    "ch_export" => "Export all running instances to a file. Usage: ch_export [file]",
		    "ch_import" => "Import all running instances from a file. Usage: ch_import [file]",
		    "ch_load_obj" => "Load an object type. Usage: ch_load_obj [type]"
		}
		end
	    
		def name
		    "CloudHerder"
		end
		
		def cmd_ch_help(*args)
			if args.empty?
				commands.each_pair {|k,v| print_line "%-20s - %s" % [k,v] }
			else
				args.each do |c|
					if extended_help[c] || commands[c]
						print_line "%-20s - %s" % [c,extended_help[c] || commands[c]]
					else
						print_error "Unknown command '#{c}'"
					end
				end
			end
		end
		
		def cmd_ch_fog(*args)
			return cmd_ch_help unless args.count == 1 
			@master = ::Lab::Drivers::FogDriver.new(self, args[0])
			print_good "Succesfully loaded #{args[0]}"
		end
		
		def cmd_ch_load(*args)
			
			clouds = @master.running
			temp = []
			adding = 0
			exists = false
			
			clouds.each do |cloud|
				temp.push(cloud)
			end
			
			unless temp[0].public_ip_address
				print_error "No running instances found." 
				return
			end
			
			#let's apply the generic obj
			temp.each do |bot|
				
				inst = ::Lab::Instance.new(@ittr)
				
				inst.server = bot
				inst.ip = bot.public_ip_address
				
				@bots.each do |key,value|
					exists = true if value.ip == inst.ip
				end
				
				@bots["#{inst.name}"] = inst unless exists
				adding = adding + 1 unless exists
				@ittr = @ittr + 1
				exists = false
			end
			
			print_good "Added #{adding} already running instances." if adding > 0
			print_error "All running instances already loaded." if adding == 0
		end
		
		def cmd_ch_load_obj(*args)
			#load the object -- there MUST be a better way to do this
			require "#{args[0]}"
		end
		
		def cmd_ch_start(*args)
			if args[0] == "local"
				print_error "Local instances cannot be started, start the instance and import it."
				return 
			end

			#provide the instance to start
			server = @master.start(args[0])
			
			if server
				inst = ::Lab::Instance.new(@ittr)
				
				@ittr = @ittr + 1
				inst.server = server
				inst.ip = server.public_ip_address
				inst.group = args[0]
				@bots["#{inst.name}"] = inst
				
				print_good "Server #{args[0]} with #{server.public_ip_address} created and added to herd."
			else
				print_error "Server creation failed.." unless server
			end
		end
		
		def cmd_ch_start_n(*args)
			return cmd_ch_help unless args.count == 2 
			print_status("Creating #{args[0]} instances of #{args[1]}")
			(1..args[0]).each do |i|
				cmd_ch_start(args[1])
			end
		end
		
		def cmd_ch_run(*args)
			return cmd_ch_help unless args.count >= 2 
			
			unless @bots["#{args[0]}"]
				print_error "#{args[0]} was not found in the running instances." 
				return
			end
		
			ip = @bots["#{args[0]}"].ip
			
			return unless ip
				
			print_line "Running #{args[1]} on #{args[0]} - #{ip}   Group:#{@bots[args[0]].group} \t \t #{Time.new}"
			
			#run the command via the driver
			@master.run_command(@bots["#{args[0]}"].base_name, ip, args[1])
			print_line " "
		end
		
		def cmd_ch_run_obj(*args)
			return cmd_ch_help unless args.count >= 2 
			
			bot = @bots["#{args[0]}"]
			unless bot
				print_error "#{args[0]} was not found."
				return
			end
			obj_cmd = bot.cmds["#{args[1]}"]			
			unless obj_cmd
				print_error "#{args[1]} command not found for this object"
				return
			end

			if obj_cmd.ssh	
				info = @master.run_command_obj(bot.base_name, bot.ip, obj_cmd.cmd)
			else
				#there has to be a better way to do this
				cmd = bot.send("#{obj_cmd.cmd}")
				puts cmd
				info = @master.run_command_obj(bot.base_name, bot.ip, cmd)
			end
			
			if info[1]
				#in case multiple pids are returned, save them all
				info[1].split(" ").each do |pid|
					bot.add_running(pid,obj_cmd.cmd,info[0])
				end
			else
				bot.history["#{info[1]}"] = obj_cmd if bot.history
			end			
		end
		
		def cmd_ch_run_group(*args)
			return cmd_ch_help unless args.count >= 2
		
			@bots.each do |name,bot|
				cmd_ch_run(name,args[1]) if bot.group == args[0]
			end
		end

		def cmd_ch_history(*args)
			return cmd_ch_help unless args.count >= 1
		
			print_line "CURRENTLY RUNNING PROCESSES"
			@bots.each do |name,bot|		
				bot.running.each do |pid,info|
					next unless pid
					print_line "#{pid}           #{info['cmd']}       #{info['stdout']}" if pid
				end
			end

			print_line "\nPROCESS HISTORY"		
			@bots.each do |name,bot|
				bot.history.each do |pid,info|
					next unless pid
					print_line "#{pid}           #{info['cmd']}       #{info['stdout']}" if pid
				end
			end
			
		end
		
		def cmd_ch_run_all(*args)
			return cmd_ch_help unless args.count >= 1
		
			@bots.each do |name,bot|
				cmd_ch_run(name,args[0])
			end
		end
		
		def cmd_ch_list
			print_error "There are 0 instances in your queue." unless @bots.length > 0
			return unless @bots.length > 0
			
			print_line "NAME                     IP                      GROUP                TYPE\n"
			@bots.each do |name,bot|
				print_line "#{name}             #{bot.ip}             #{bot.group}              #{bot.obj_type}"
			end
			print_line " "
			
		end
		
		def cmd_ch_scp_file(*args)
			#local file, name, ip, remote location
			raise "Not implemented. Use net::ssh rather net::scp and create file buffer."
		end
		
		def cmd_ch_clear
			@bots = Hash.new
			@ittr = 0
			print_status "Bot set emptied out."
		end
		
		def cmd_ch_rename(*args)
			temp = @bots["#{args[0]}"]
			print_error "#{args[0]} was not found in the running instances." unless temp
			return unless temp
		
			@bots.delete("#{args[0]}")
			@bots["#{args[1]}"] = temp
			print_status "Renamed #{args[0]} to #{args[1]}"
		end
		
		def cmd_ch_stop(*args)
			return cmd_ch_help unless args.count >= 2
			
			cmd_ch_run(args[0],"sudo kill #{args[1]}")
			@bots["#{args[0]}"].finished(args[1])
		end
		
		def cmd_ch_stopall
			@bots.each do |name,bot|
				bot.running.each do |pid,info|
					cmd_ch_run(name,"sudo kill #{pid}")
					@bots["#{name}"].finished(pid)
				end
			end
			
			
		end
		
		def cmd_ch_set_obj(*args)
			return cmd_ch_help unless args.count >= 2

			temp = @bots["#{args[0]}"]
			print_error "#{args[0]} was not found in the running instances." unless temp
			return unless temp	

			temp.obj_type = args[1]
			
			#!!! Dangerrrr. This is a terrible idea, but idk how else to use reflection in this case
			inst =  eval("Lab::#{args[1]}").new(temp)
			
			@bots["#{args[0]}"] = inst
		end
		
		def cmd_ch_export(*args)
			File.open(args[0],'w') do|file|
				@bots.each do |name,bot|
					file.puts "- name: exported_#{@ittr}"
					file.puts "  ip: #{bot.ip}"
					file.puts "  obj_type: #{bot.obj_type}"
					file.puts "  group: #{bot.group}"
					file.puts "  non_fog: #{bot.non_fog}"
					file.puts "  fog_type: #{bot.fog_type}"
					file.puts "  base_name: #{bot.base_name}"
				end
			end
		end
		
		def cmd_ch_import(*args)
			temp = []
			robots = {}
			
			clouds = @master.running
			#ping the fog server so we can load server objects
			clouds.each do |cloud|
				temp.push(cloud)
			end
		
			temp.each do |bot|
				robots["#{bot.public_ip_address}"] = bot	
			end
			
			#load the instances
			@instances= YAML::load_file(args[0])
			@instances.each do |instance|
				if instance['obj_type'] != "instance"
					#this is foolish, need a better way
					cmd_ch_load_obj(instance['obj_type'].downcase)
					inst = eval("Lab::#{instance['obj_type']}").new(nil)
				else
					inst = ::Lab::Instance.new(1)
				end
				
				inst.ip = instance['ip']
				inst.group = instance['group']
				inst.name = instance['name']
				inst.fog_type = instance['fog_type']
				inst.base_name = instance['base_name']
				
				#build the server object
				if instance['non_fog']
					#we need a generic server obj
					inst.server = ::Lab::Instance::Server.new(instance['ip'])
				else
					inst.server = robots["#{instance['ip']}"] if robots.key?("#{instance['ip']}")
				end
				@bots["#{inst.name}"] = inst
			end
		end
end
	
	#
	# The constructor is called when an instance of the plugin is created.  The
	# framework instance that the plugin is being associated with is passed in
	# the framework parameter.  Plugins should call the parent constructor when
	# inheriting from Msf::Plugin to ensure that the framework attribute on
	# their instance gets set.
	#
	def initialize(framework, opts)
		super

		## Register the commands above
		console_dispatcher = add_console_dispatcher(BotCommandDispatcher)

		@controller = ::Lab::Controllers::VmController.new
		## Share the vms
		console_dispatcher.controller = @controller

	end


	#
	# The cleanup routine for plugins gives them a chance to undo any actions
	# they may have done to the framework.  For instance, if a console
	# dispatcher was added, then it should be removed in the cleanup routine.
	#
	def cleanup
		# If we had previously registered a console dispatcher with the console,
		# deregister it now.
		remove_console_dispatcher('CloudHerder')
	end

	#
	# This method returns a short, friendly name for the plugin.
	#
	def name
		"CloudHerder"
	end

	#
	# This method returns a brief description of the plugin.  It should be no
	# more than 60 characters, but there are no hard limits.
	#
	def desc
		"Manage some cloud instances."
	end

end #class
end #module