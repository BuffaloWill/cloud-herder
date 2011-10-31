require 'vm'

module Lab
class Pwcrack < Instance  
	# a verrrry basic example. A password is pulled from the default workspace
	#   and sent to a remote instance. Assuming jtr is already set to run so
	#   often on passwords.txt.
	
	def initialize(info)
		self.obj_type = "Pwcrack"
		self.cmds = obj_commands
		self.history = {}
		self.running = {}
		if info
			self.name = info.name 
			self.base_name = info.base_name 
			self.server = info.server 
			self.ip = info.ip 
			self.history = info.history 
			self.group = info.group 
			self.running = info.running 
			self.ami = info.ami 
		end
	end
	
	def crack_cred
		#read passes from the default database
		wspace = Msf::DBManager::Workspace.find_by_name('default')

		hashlist = ""
		#taken from jtr_fast
		smb_hashes = wspace.creds.select{|x| x.ptype == "smb_hash" }
		smb_hashes.each do |cred|
			hashlist << "cred_#{cred[:id]}:#{cred[:id]}:#{cred[:pass]}:::\n"
				
		end
		
		puts "Sending passwords to remote instance for cracking.."
		#this is awful but, until scp is inplace, it works
		return "echo '#{hashlist.chop}' >> passwords.txt;"
		
	end
	def obj_commands()
		return {
			"randoms" => Command.new({ "ssh" => true, "cmd" => "cat /dev/random"}),
			"crack" => Command.new({ "ssh" => false, "cmd" => "crack_cred" })
			}	
	end
	
end
end