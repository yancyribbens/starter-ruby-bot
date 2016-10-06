require 'slack-ruby-client'
require 'logging'
require 'httparty'

logger = Logging.logger(STDOUT)
logger.level = :debug

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
  if not config.token
    logger.fatal('Missing ENV[SLACK_TOKEN]! Exiting program')
    exit
  end
end

client = Slack::RealTime::Client.new

# listen for hello (connection) event - https://api.slack.com/events/hello
client.on :hello do
  logger.debug("Connected '#{client.self['name']}' to '#{client.team['name']}' team at https://#{client.team['domain']}.slack.com.")
end

# listen for channel_joined event - https://api.slack.com/events/channel_joined
client.on :channel_joined do |data|
  if joiner_is_bot?(client, data)
    client.message channel: data['channel']['id'], text: "Thanks for the invite! I don\'t do much yet, but #{help}"
    logger.debug("#{client.self['name']} joined channel #{data['channel']['id']}")
  else
    logger.debug("Someone far less important than #{client.self['name']} joined #{data['channel']['id']}")
  end
end

def match_uuid(data)
	data.match(/.*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*/)[1]
end

def acclaim_badge(data)
	badge_id = match_uuid(data)
	if badge_id
		HTTParty.get(
			"https://api.youracclaim.com/v1/organizations/adbb05be-a298-44ab-88c7-e7e11af5f345/badges/#{badge_id}",
			:basic_auth => { :username => ENV['ACCLAIM_TOKEN'], :password => '' }
		)
	end
end

def acclaim_badge_template(data)
	badge_template_id = match_uuid(data)
	if badge_template_id
		HTTParty.get(
			"https://api.youracclaim.com/v1/organizations/adbb05be-a298-44ab-88c7-e7e11af5f345/badge_templates/#{badge_template_id}",
			:basic_auth => { :username => ENV['ACCLAIM_TOKEN'], :password => '' }
		)
	end
end

def standard_size_image_url(url)
  uri = URI(url)
  path_array = uri.path.split('/')
  file = path_array.pop
  new_file = 'standard_' + file
  new_path = (path_array.push new_file).join('/')
  uri.path = new_path
  uri.to_s
end

def template_to_attachment(data)
  template = acclaim_badge_template(data)
  [
    {
      title: template["data"]["name"],
      image_url: standard_size_image_url(template["data"]["image"]["url"]),
      title_link: template["data"]["url"],
      text: template["data"]["description"]
    }
  ]
end

# listen for message event - https://api.slack.com/events/message
client.on :message do |data|

  case data['text']
  when 'hi', 'bot hi' then
    client.typing channel: data['channel']
    client.message channel: data['channel'], text: "Hello <@#{data['user']}>."
    logger.debug("<@#{data['user']}> said hi")

    if direct_message?(data)
      client.message channel: data['channel'], text: "It\'s nice to talk to you directly."
      logger.debug("And it was a direct message")
    end

  when 'attachment', 'bot attachment' then
    # attachment messages require using web_client
    client.web_client.chat_postMessage(post_message_payload(data))
    logger.debug("Attachment message posted")

  when bot_mentioned(client)
    client.message channel: data['channel'], text: 'You really do care about me. :heart:'
    logger.debug("Bot mentioned in channel #{data['channel']}")

  when 'bot help', 'help' then
    client.message channel: data['channel'], text: help
    logger.debug("A call for help")

  when /.*badge ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*/ then
    client.message channel: data['channel'], text: 'under construction'
		#response = acclaim_badge(data['text'])
		#url = response.dig('data', 'image', 'url') 
		#if url 
			#client.message channel: data['channel'], text: response['data']['image']['url']
		#end

  when /.*badge template ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*/ then
    client.web_client.chat_postMessage(
      {
        channel: data['channel'],
        as_user: true,
        attachments: template_to_attachment(data['text'])
      }
    )

		#client.web_client.chat_postMessage(
		#{
			#channel: data['channel'],
			#as_user: true,
			#attachments: [
        #{
            #"fallback": "Required plain-text summary of the attachment.",
            #"color": "#36a64f",
            #"author_name": "Acclaim",
            #"title": "Acclaim Early Adopter",
						#"image_url": "https://acclaim-production-app.s3.amazonaws.com/images/482a8c1c-b984-41aa-b30a-3a038fa1e7cc/standard_bcfff5e98770d9ee81a517561c72b8f0f9b9fa6f.png",
            #"text": "An achievement for individuals who dedicated time and energy into helping Acclaim launch. While this badge may not have much in terms of value or rigor, it does recognize an individual's dedication to being a team player and helping when asked.",
            #"footer": "Slack API",
            #"footer_icon": "https://platform.slack-edge.com/img/default_application_icon.png",
            #"ts": 123456789
        #}
      #]
		#}
		#)
		#client.message channel: data['channel'], attachments: '[{"pretext": "pre-hello", "text": "text-world"}]'
 
		#response = acclaim_badge_template(data['text'])
		#url = response.dig('data', 'image', 'url') 
		#if url 
			#client.message channel: data['channel'], text: response['data']['image']['url']
		#end

  when /^bot/ then
    client.message channel: data['channel'], text: "Sorry <@#{data['user']}>, I don\'t understand. \n#{help}"
    logger.debug("Unknown command")
  end
end

def direct_message?(data)
  # direct message channles start with a 'D'
  data['channel'][0] == 'D'
end

def bot_mentioned(client)
  # match on any instances of `<@bot_id>` in the message
  /\<\@#{client.self['id']}\>+/
end

def joiner_is_bot?(client, data)
 /^\<\@#{client.self['id']}\>/.match data['channel']['latest']['text']
end

def help
  %Q(I will respond to the following messages: \n
      `bot hi` for a simple message.\n
      `bot attachment` to see a Slack attachment message.\n
      `@<your bot\'s name>` to demonstrate detecting a mention.\n
      `bot help` to see this again.)
end

def post_message_payload(data)
  main_msg = 'Beep Beep Boop is a ridiculously simple hosting platform for your Slackbots.'
  {
    channel: data['channel'],
      as_user: true,
      attachments: [
        {
          fallback: main_msg,
          pretext: 'We bring bots to life. :sunglasses: :thumbsup:',
          title: 'Host, deploy and share your bot in seconds.',
          image_url: 'https://storage.googleapis.com/beepboophq/_assets/bot-1.22f6fb.png',
          title_link: 'https://beepboophq.com/',
          text: main_msg,
          color: '#7CD197'
        }
      ]
  }
end

client.start!
