require 'vm'

module Lab
class Instance < Lab::Vm  
	attr_accessor :name
	attr_accessor :base_name
	attr_accessor :server
	attr_accessor :ip
	attr_accessor :history
	attr_accessor :group
	attr_accessor :running
	attr_accessor :ami
	attr_accessor :cmds
	attr_accessor :obj_type
	attr_accessor :non_fog
	attr_accessor :fog_type

	def initialize(ittr)
		self.base_name = "instance"
		self.name = "#{base_name}_#{ittr}"
		self.group = "instance"
		self.ami = "instance"
		self.history = {}
		self.running = {}
		self.cmds = obj_commands
		self.obj_type = "Instance"
	end
	
	def add_running(*args)
		#pid, process
		running["#{args[0]}"] =
			{
				"cmd" => args[1],
				"stdout" => args[2]
			}	unless running.key?("#{args[0]}")
	end
		
	def finished(*args)
		cmd = running.delete(args[0])
		history["#{args[0]}"] = cmd
	end
	
	def obj_commands()
		#every object should implement it's own set of commands
		# this is an example
		
		return {
			"random" => Command.new({ "ssh" => true, "cmd" => "cat /dev/random"})
			}
	end
	
	def to_hash(server_obj)
		hash = {}
		server_obj.attributes.each { |k,v| hash[k] = v }
		return hash
	end
	
	class Command
		attr_accessor :ssh
		attr_accessor :cmd
		attr_accessor :desc
		
		def initialize(attr)
			self.ssh = attr["ssh"]
			self.cmd = attr["cmd"]
		end
	end
	
	class Server
		attr_accessor :public_ip_address
		
		def initialize(ip)
			self.public_ip_address = ip
		end
	end
end
end