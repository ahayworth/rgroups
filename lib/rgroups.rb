require 'mechanize'


class RGroup
    @@MANAGE     = '/manage_members'
    @@DIRECT_ADD = '/manage_members_add'
    @@INVITE_ADD = '/members_invite'
	@@GROUP_SETTINGS = '/manage_general'
	@@ACCESS_SETTINGS = '/manage_access'
	@@POST_SETTINGS = '/manage_post'
	@@ADV_SETTINGS = '/manage_advanced'
	@@SPAM_SETTINGS = '/manage_spam'
	@@BASE = 'https://groups.google.com'
	@@GAFYD_BASE = 'https://groups.google.com/a/'
	@@SUBS = '/groups/mysubs'
	
    def initialize(*gafyd)
        @scraper = Mechanize.new
        @scraper.reuse_ssl_sessions = false
        if (gafyd.length == 0) 
        	@LIST_GROUPS = @@BASE + @@SUBS
            @BASE_URL = @@BASE + '/group/'
            @LOGIN_URL = 'https://accounts.google.com/ServiceLogin?service=groups2&passive=1209600&continue=https://groups.google.com/&followup=https://groups.google.com/'
        else
        	@GAFYD = true
            @GAFYD_DOMAIN = gafyd[0]
        	@LIST_GROUPS = @@GAFYD_BASE + @GAFYD_DOMAIN + @@SUBS
            @BASE_URL = @@GAFYD_BASE + @GAFYD_DOMAIN + "/group/"
            @LOGIN_URL = @@GAFYD_BASE + @GAFYD_DOMAIN
        end
    end
	
	# login to google apps
    def login(username, password)
        page = @scraper.get(@LOGIN_URL)
        f = page.forms[0]
        f.Email = username
        f.Passwd = password
        @scraper.submit(f, f.buttons.first)
    end
	
	# groups that the logged-in user is subscribed to
	def subscribed_groups
		page = @scraper.get(@LIST_GROUPS)
		groups = []
		page.search('//a[@class="on"]').each do |link|
			parts = link[:href].split("/")
			groups << parts[parts.length - 1]
		end
		
		groups
	end
	
	#search groups
	#listing groups is not easy when scraping
	#instead, you can search for one
	#returns first 15 results, anything else is real slow
	def search_groups(group)
		if (@GAFYD)
			page = @scraper.get(@@GAFYD_BASE + @GAFYD_DOMAIN)
		else
			page = @scraper.get(@@BASE)
		end
		
		form = page.form('gs2')
		form.q = group
		page = @scraper.submit(form, form.button_with(:name => "qt_s"))
		groups = []
		page.search('//a[@class="on"]').each do |link|
			parts = link[:href].split("/")
			parts = parts[parts.length - 1].split("?")
			groups << parts[0] unless parts[0].eql?("advanced_search")
		end
		
		return nil if groups.length == 0
		groups
	end
	
	#post a message to groups
	def post_message(group, subject, message, send_copy=false, cc='')
		page = @scraper.get(@BASE_URL + group + '/topics')
		if (@GAFYD)
			form = page.form_with(:action => '/a/' + @GAFYD_DOMAIN + '/group/' + group + "/post")
		else
			form = page.form_with(:action =>  "/group/" + group + "/post")
		end
		page = @scraper.submit(form, form.button_with(:value => "+ New post"))
		
		form = page.form('postform')
		form.cc = cc
		form.subject = subject
		form.body = message
		
		if (send_copy)
			form.checkbox_with(:name => 'bccme').check
		end
		
		@scraper.submit(form, form.button_with(:name => 'Action.Post'))
	end
	
	#lists the most recent topics in a group
	def get_topics(group)
		topics = {}
		page = @scraper.get(@BASE_URL + group + '/topics?gvc=2')
		page.search('//div[@class="maincontoutboxatt"]//table//a').each do |link|
			unless(link[:class] == "st")
				topics[link.inner_text.strip] = @@BASE + link[:href]
			end
		end
		
		topics
	end
	
	
	# add a user
	# email = email address to add
	# group = group name
	# :mode => direct (only for gafyd accounts)
	# :notify => true/false to notify users they've been added (only for gafyd)
	# :delivery => only for gafyd
	# - none, email, summary, one
	# :message => message to send to person when being added
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
    
    # update a user
	# email = email address to update
	# group = group name
	# action = set_member, set_email
	# :value => depends on what you're doing. 
	# - set_member: regular, manager, owner, unsubscribe, ban
	# - set_email: none, email, summary, one
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
	
	# return a hash of group settings
	def settings(group)
		settings = {}
		
		page = @scraper.get(@BASE_URL + group + @@GROUP_SETTINGS)
		settings['group_name'] = page.search('//div[@id="name_view"]').text.strip
		settings['group_description'] = page.search('//div[@id="desc_view"]').text.strip
		settings['group_website'] = page.search('//div[@id="info_url_view"]').text.strip
		
		
		page = @scraper.get(@BASE_URL + group + @@ACCESS_SETTINGS)
		form = page.form_with(:id => "GM_form")
		if (@GAFYD)
			settings['allow_external']  = form.checkbox_with(:name => 'param.allow_external_members').checked?
		end
		form.radiobuttons_with(:name => 'param.archive_view').each do |r|
			settings['archive_view'] = r.value if r.checked?
		end
		form.radiobuttons_with(:name => 'param.members_view').each do |r|
			settings['member_view'] = r.value if r.checked?
		end
		form.radiobuttons_with(:name => 'param.who_can_join').each do |r|
			settings['can_join'] = r.value if r.checked?
		end
		settings['join_question'] = form.field_with(:name => 'param.join_question').value.strip
		form.radiobuttons_with(:name => 'param.who_can_post').each do |r|
			settings['who_can_post'] = "managers" if r.checked?  && r.value == 'm'
			settings['who_can_post'] = "members" if r.checked?  && r.value == 's'
			settings['who_can_post'] = "domain" if r.checked?  && r.value == 'd'
			settings['who_can_post'] = "anyone" if r.checked?  && r.value == 'p'
		end
		settings['mod_non_members']  = form.checkbox_with(:name => 'param.mod_non_members').checked?
		settings['web_posting']  = form.checkbox_with(:name => 'param.allow_web_posting').checked?
		form.radiobuttons_with(:name => 'param.who_can_invite').each do |r|
			settings['who_can_invite'] = r.value if r.checked?
		end
		form.radiobuttons_with(:name => 'param.msg_moderation').each do |r|
			settings['msg_moderation'] = r.value if r.checked?
		end
		settings['mod_new_members']  = form.checkbox_with(:name => 'param.mod_new_members').checked?
		
		
		page = @scraper.get(@BASE_URL + group + @@POST_SETTINGS)
		form = page.form_with(:id => "GM_form")
		if (@GAFYD)
			settings['custom_reply_to'] = form.field_with(:name => 'param.custom_reply_to').value.strip
			form.field_with(:name => 'param.max_size').options.each do |s|
				settings['max_size'] = s.value if s.selected?
			end
			settings['reply_with_bounce_list']  = form.checkbox_with(:name => 'param.reply_with_bounce_list').checked?
		end
		settings['subject_tag'] = form.field_with(:name => 'param.subject_tag').value.strip
		form.radiobuttons_with(:name => 'param.footer').each do |r|
			settings['message_footer'] = "none" if r.checked?  && r.value == 'n'
			settings['message_footer'] = "default" if r.checked?  && r.value == 'd'
			settings['message_footer'] = "custom" if r.checked?  && r.value == 'c'
		end
		settings['reply_to'] = form.field_with(:name => 'param.footer_text').value.strip
		form.radiobuttons_with(:name => 'param.reply_to').each do |r|
			settings['reply_to'] = "whole_group" if r.checked?  && r.value == 'l'
			settings['reply_to'] = "author" if r.checked?  && r.value == 'a'
			settings['reply_to'] = "owner" if r.checked?  && r.value == 'o'
			settings['reply_to'] = "user_decide" if r.checked?  && r.value == 'n'
			settings['reply_to'] = "custom" if r.checked?  && r.value == 'c'
		end
		settings['posting_as_group']  = form.checkbox_with(:name => 'param.posting_as_group').checked?
		settings['moderation_notify']  = form.checkbox_with(:name => 'param.moderation_notify').checked?
		settings['moderation_message_text'] = form.field_with(:name => 'param.footer_text').value.strip

		page = @scraper.get(@BASE_URL + group + @@ADV_SETTINGS)
		form = page.form_with(:id => "GM_form")
		form.field_with(:name => 'param.lang').options.each do |s|
			settings['primary_language'] = s.value if s.selected?
		end
		settings['fixed_font']  = form.checkbox_with(:name => 'param.font_type').checked?
		settings['no_archive_msgs']  = form.checkbox_with(:name => 'param.no_archive').checked?
		settings['group_is_archived']  = form.checkbox_with(:name => 'param.status_archive').checked?
		settings['google_contact']  = form.checkbox_with(:name => 'param.can_contact').checked?
		
		page = @scraper.get(@BASE_URL + group + @@SPAM_SETTINGS)
		form = page.form_with(:id => "GM_form")
		form.radiobuttons_with(:name => 'param.spam_mode').each do |r|
			settings['spam_mode'] = "post" if r.checked?  && r.value == '0'
			settings['spam_mode'] = "mod" if r.checked?  && r.value == '1'
			settings['spam_mode'] = "mod_quiet" if r.checked?  && r.value == '3'
			settings['spam_mode'] = "reject" if r.checked?  && r.value == '2'
		end
		return settings
	end
	
end

# monkey-patch Mechanize::HTTP::Agent so we can't reuse ssl sessions
# as that seems to break things
class Mechanize::HTTP::Agent
    def reuse_ssl_sessions
        @http.reuse_ssl_sessions
    end

    def reuse_ssl_sessions= reuse_ssl_sessions
        @http.reuse_ssl_sessions = reuse_ssl_sessions
    end
end

# monkey-patch Mechanize so we can't reuse ssl sessions
# as that seems to break things
class Mechanize
    def reuse_ssl_sessions
        @agent.reuse_ssl_sessions
    end

    def reuse_ssl_sessions= reuse_ssl_sessions
        @agent.reuse_ssl_sessions = reuse_ssl_sessions
    end
end