require 'google/api_client'
require 'json'
#t
#USERS = %w(admin@procnc.com andrewm@procnc.com andyg@procnc.com benj@procnc.com bens@procnc.com bethw@procnc.com brentj@procnc.com briana@procnc.com bruceb@procnc.com calebb@procnc.com chuckb@procnc.com conferenceroom@procnc.com danah@procnc.com darcy@procnc.com erics@procnc.com jasin@procnc.com jimb@procnc.com jone@procnc.com JoshK@procnc.com kellym@procnc.com kelsey@procnc.com kens@procnc.com laurier@procnc.com leenad@procnc.com library@procnc.com mandym@procnc.com marcusc@procnc.com matt@procnc.com matta@procnc.com mattz@procnc.com michaelh@procnc.com mikel@procnc.com mikes@procnc.com oleb@procnc.com paul@procnc.com quotes@procnc.com robertk@procnc.com robr@procnc.com russs@procnc.com scottp@procnc.com shawnh@procnc.com travish@procnc.com tuil@procnc.com zach@procnc.com)
USERS = %w(benj@procnc.com kelsey@procnc.com darcy@procnc.com matta@procnc.com mikes@procnc.com zach@procnc.com paul@procnc.com jone@procnc.com)

OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE # This awful hack fixes ruby's deffault implementation (no certificates are trusted)

## Email of the Service Account #
SERVICE_ACCOUNT_EMAIL = '910317984246@developer.gserviceaccount.com'

## Path to the Service Account's Private Key file #
SERVICE_ACCOUNT_PKCS12_FILE_PATH = '05d7420f32286bca9c1275a76a693ed699126acb-privatekey.p12'

##
# Build a Drive client instance authorized with the service account
# that acts on behalf of the given user.
#
# @param [String] user_email
#   The email of the user.
# @return [Google::APIClient]
#   Client instance
def build_client(user_email)
	key = Google::APIClient::PKCS12.load_key(SERVICE_ACCOUNT_PKCS12_FILE_PATH, 'notasecret')
	asserter = Google::APIClient::JWTAsserter.new(SERVICE_ACCOUNT_EMAIL,
	'https://www.googleapis.com/auth/tasks', key)
	client = Google::APIClient.new
	client.authorization = asserter.authorize(user_email)
	client
end

def get_users_tasks(user, tasklist = '@default')
	api_client = build_client(user)
	tasks_api = api_client.discovered_api('tasks', 'v1')

	api_client.execute(tasks_api.tasks.list, 'tasklist' => tasklist)
end

to_do = {}

USERS.each do |user|
	result = get_users_tasks(user)

	if result.status == 200
		tasks = result.data
	else
		puts "#{user}: An error occurred: #{result.data}"
		next
  end
  puts user
  puts tasks.inspect

	tasks['items'].each do |task|
		words = (task['notes'] ? task['notes'].split(' ') : []) + (task['title'] ? task['title'].split(' ') : [])
    puts 'All words:' + words.inspect
		words = words.find_all { |x| x[0] == '@' }
    puts 'with @' + words.inspect
		next if words.empty?


		words.each do |word|
			word = word[1..-1] # Strip out the @
      word = word.downcase
      puts word
      if USERS.include?(word + '@procnc.com')
        to_do[word + '@procnc.com'] ||= []
        to_do[word + '@procnc.com'] << { title: task['title'], notes: task['notes'], referencer: user.split('@')[0] }
      end
		end
	end
end

USERS.each do |user|
  client = build_client(user)
  tasks_api = client.discovered_api('tasks', 'v1')

  res = client.execute(api_method: tasks_api.tasklists.list)
  res.data['items'].each do |tasklist|
    if tasklist.title[0] == '@'
      client.execute(api_method: tasks_api.tasklists.delete,
                     parameters: {'tasklist' => tasklist['id']})
    end
  end
end

to_do.each do |user, tasks|
  client = build_client(user)
  tasks_api = client.discovered_api('tasks', 'v1')

  tasks.each do |task|
    # Does referencer tasklikt exist?
    list = false
    client.execute(tasks_api.tasklists.list).data['items'].each do |item| # Go through each list
      list = item['id'] if item['title'] == '@' + task[:referencer] # Find list
    end

    unless list
      res = client.execute(api_method: tasks_api.tasklists.insert, # Make the list
                           body: JSON.dump({ 'title' => '@' + task[:referencer] }),
                           headers: {'Content-Type' => 'application/json'})
      list = res.data.id
    end

    client.execute(api_method: tasks_api.tasks.insert, # Make the task
                   parameters: { 'tasklist' => list },
                   body: JSON.dump({ 'title' => task[:title], 'notes' => task[:notes] }),
                   headers: {'Content-Type' => 'application/json'})
  end
end
