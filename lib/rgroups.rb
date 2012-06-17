require 'mechanize'


class RGroup
    @@MANAGE     = '/manage_members'
    @@DIRECT_ADD = '/manage_members_add'
    @@INVITE_ADD = '/members_invite'
	@@GROUP_SETTINGS = '/manage_general'
	
    def initialize(*gafyd)
        @scraper = Mechanize.new
        @scraper.reuse_ssl_sessions = false
        if (gafyd.length == 0) 
            @BASE_URL = 'https://groups.google.com/group/'
            @LOGIN_URL = 'https://accounts.google.com/ServiceLogin?service=groups2&passive=1209600&continue=https://groups.google.com/&followup=https://groups.google.com/'
        else
            @BASE_URL = 'https://groups.google.com/a/' + gafyd[0] + "/group/"
            @LOGIN_URL = 'https://groups.google.com/a/' + gafyd[0]
            @GAFYD = true
        end
    end

    def login(username, password)
        page = @scraper.get(@LOGIN_URL)
        f = page.forms[0]
        f.Email = username
        f.Passwd = password
        @scraper.submit(f, f.buttons.first)
    end
	
	def add_user(email, group, opts={})
		if (opts[:mode] && opts[:mode].downcase == "direct")
			raise "direct add mode is only available for gafyd accounts" unless @GAFYD
			page = @scraper.get(@BASE_URL + group + @@DIRECT_ADD)
			member_form = page.form('cr')
			if (email.is_a? Array)
				member_form.members_new = email.join(", ")
			else
				member_form.members_new = email
			end
			
			if (opts[:notify]) 
				member_form.body = opts[:message]
				member_form.checkbox_with(:name => 'notification').check
			elsif (!opts[:notify] || opts[:notify].nil?)
				member_form.checkbox_with(:name => 'notification').uncheck
			end        
	
			if (opts[:delivery])
				case opts[:delivery]
					when "none"
						member_form.radiobuttons_with(:name => 'delivery')[0].check
					when "email"
						member_form.radiobuttons_with(:name => 'delivery')[1].check
					when "summary"
						member_form.radiobuttons_with(:name => 'delivery')[2].check
					when "one"
						member_form.radiobuttons_with(:name => 'delivery')[3].check
					else
						member_form.radiobuttons_with(:name => 'delivery')[0].check
				end
			end
		else # we're going to invite, not add
			page = @scraper.get(@BASE_URL + group + @@INVITE_ADD)
			member_form = page.form('cr')
			if (email.is_a? Array)
				member_form.members_new = email.join(", ")
			else
				member_form.members_new = email
			end
			member_form.body = opts[:message]
		end
		@scraper.submit(member_form, member_form.button_with(:name => 'Action.InitialAddMembers'))
	end
    
    def update_user(email, group, action, opts={})
        page = @scraper.get(@BASE_URL + group + @@MANAGE)
		member_set = page.search('//table[@class="memlist"]//td')
		members = []
		member_set.each do |m| 
			members.push(member_set[member_set.index(m) + 1]) if m.to_s.include?('class="cb"')
		end 
		
		member_form = page.form('memberlist')
		email.downcase!
		index = nil 
		members.each_index do |m| 
			index = m if members[m].to_s.downcase.include?(email)
		end 
	
		member_form.checkboxes_with(:name => 'subcheckbox')[index].check unless index.nil?
		
		if (action.downcase == "set_member")
			case opts[:value]
				when "regular"
					member_form.field_with(:name => 'membership_type').options[1].select
				when "manager"
					member_form.field_with(:name => 'membership_type').options[2].select
				when "owner"
					member_form.field_with(:name => 'membership_type').options[3].select
				when "unsubscribe"
					member_form.field_with(:name => 'membership_type').options[5].select
				when "ban"
					member_form.field_with(:name => 'membership_type').options[6].select
			end
			@scraper.submit(member_form, member_form.button_with(:name => 'Action.SetMembershipType'))
		elsif (action.downcase == "set_email")
			case opts[:value]
				when "none"
					member_form.field_with(:name => 'delivery').options[1].select
				when "email"
					member_form.field_with(:name => 'delivery').options[2].select
				when "summary"
					member_form.field_with(:name => 'delivery').options[3].select
				when "one"
					member_form.field_with(:name => 'delivery').options[4].select
			end
			@scraper.submit(member_form, member_form.button_with(:name => 'Action.SetDeliveryType'))
		end	
		
	end
	
end

# monkey-patch Mechanize so we can't reuse ssl sessions
# as that seems to break things
class Mechanize::HTTP::Agent
    def reuse_ssl_sessions
        @http.reuse_ssl_sessions
    end

    def reuse_ssl_sessions= reuse_ssl_sessions
        @http.reuse_ssl_sessions = reuse_ssl_sessions
    end
end

class Mechanize
    def reuse_ssl_sessions
        @agent.reuse_ssl_sessions
    end

    def reuse_ssl_sessions= reuse_ssl_sessions
        @agent.reuse_ssl_sessions = reuse_ssl_sessions
    end
end