require 'vm_driver'

##
## $Id$
##

module Lab
module Drivers
class FogDriver < VmDriver

	def initialize(config,fog_config)
		
		@fog_config = YAML::load_file(fog_config)
		@instances = {}
		
		# Soft dependency
		begin
			require 'fog'
		rescue LoadError
			raise "WARNING: Library fog not found. Could Not Create Driver"
		end

		@fog_config.each do |instance|
			
			#add all global configuration information
			if instance['name'] == "global" and instance['fog_type'] == "ec2"
	
				# AWS / EC2 Base Credential Configuration
				@aws_cert_file = IO.read(instance['fog_aws_cert_file']).chomp if instance['fog_aws_cert_file']
				@aws_private_key_file = IO.read(instance['fog_aws_private_key_file']).chomp if instance['fog_aws_private_key_file']
				@ec2_access_key = instance['fog_ec2_access_key']
				@ec2_secret_access_key = instance['fog_ec2_secret_access_key']
				
			# Set up a connection
				@compute = Fog::Compute.new(
					:provider => "AWS",
					:aws_access_key_id => "#{@ec2_access_key}",
					:aws_secret_access_key => "#{@ec2_secret_access_key}" )
				
			else if (instance['fog_type'] == "ec2")
				#add the new instance
				@instances["#{instance['name']}"] =
				{
					"fog_ec2_base_ami" => instance['fog_ec2_base_ami'],
					"fog_ec2_flavor" => instance['fog_ec2_flavor'],
					"fog_ec2_key_name" => instance['fog_ec2_key_name'],
					"fog_user" => instance['fog_user'],
					"fog_instance_private_key_file" => IO.read(instance['fog_instance_private_key_file']).chomp
				}
			else if (instance['fog_type'] == "local")
				#add the local instance
				@instances["#{instance['name']}"] =
				{
					"fog_user" => instance['fog_user'],
					"fog_instance_private_key_file" => IO.read(instance['fog_instance_private_key_file']).chomp
				}
			else
				raise "Unsupported Fog Type"
			end
		end
	end

	def start(name)
		if name == "local"
			puts "Local instances cannot be started, start the instance and import it."
			exit
		end
		begin
			server = @compute.servers.create(
							 :image_id => @instances["#{name}"]['fog_ec2_base_ami'],
							 :flavor_id => @instances["#{name}"]['fog_ec2_flavor'],
							 :key_name => @instances["#{name}"]['fog_ec2_key_name'])

			puts "Starting instance #{name}, blocking this thread until it's ready..."
			server.wait_for { ready? }
			return server
		rescue Fog::Compute::AWS::Error => e
			raise "Error: #{e}"
			exit
		end
	end
	
	def running
		return @compute.servers()
	end
	
	def run_command(name, ip, command)
		key = read_key(@instances["#{name}"]["fog_instance_private_key_file"])
		return nil unless key

		Net::SSH.start(ip, "#{@instances["#{name}"]["fog_user"]}",
			:auth_methods => "publickey",
			:key_data => key) do |ssh|
          
				ssh.open_channel do |channel|
					channel.exec(command) do |ch, stream, data|
						channel.on_extended_data do |ch, type, data|
							puts "#{data}"
						end

						channel.on_data do |ch, data|
							puts "#{data}" 
            
							# could add in the ability to send stuff here
							#channel.send_data "something for stdin\n"
						end

						channel.on_close do |ch|
							puts "Closing the connection to #{ip}..\n"
						end
					end
				end
			end
		end
	end
	
	def run_command_obj(name, ip, command)
		
		key = read_key(@instances["#{name}"]["fog_instance_private_key_file"])
		return nil unless key
		
		stdout = Rex::Text.rand_text_alpha_lower(6)
		pid = nil

		Net::SSH.start(ip, "#{ @instances["#{name}"]["fog_user"]}",
			:auth_methods => "publickey",
			:key_data => key,
			:paranoid => false) do |ssh|
          
			ssh.exec!("nohup #{command} > /tmp/#{stdout}.log 2>&1 &")
			
			pid = ssh.exec!("pidof #{command.split(" ")[0]}")
		end
	
		return [stdout,pid]	
	end

	#stolen from ssh_login_pubkey scanner, modified slightly
	def read_key(keyfile)
		keys = []
		this_key = []
		in_key = false
		keyfile.split("\n").each do |line|
			in_key = true if(line =~ /^-----BEGIN [RD]SA PRIVATE KEY-----/)
			this_key << line if in_key
			if(line =~ /^-----END [RD]SA PRIVATE KEY-----/)
				in_key = false
				keys << (this_key.join("\n") + "\n")
				this_key = []
			end
		end
		if keys.empty?
			puts "SSH - No keys found."
		end
		return validate_keys(keys)
	end

	# completely stolen
	# Validates that the key isn't total garbage. Also throws out SSH2 keys --
	# can't use 'em for Net::SSH.
	def validate_keys(keys)
		keepers = []
		keys.each do |key|
			# Needs a beginning
			next unless key =~ /^-----BEGIN [RD]SA PRIVATE KEY-----\x0d?\x0a/m
			# Needs an end
			next unless key =~ /\n-----END [RD]SA PRIVATE KEY-----\x0d?\x0a?$/m
			# Shouldn't have binary.
			next unless key.scan(/[\x00-\x08\x0b\x0c\x0e-\x1f\x80-\xff]/).empty?
			# Add more tests to taste.
			keepers << key
		end
		if keepers.empty?
			puts "SSH - No valid keys found"
		end
		return keepers
	end

	def stop
		@fog_server.destroy
	end


end
end 
end
end
