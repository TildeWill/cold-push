#!/usr/bin/env ruby
require 'erb'
require 'yaml'
require 'json'
require 'highline/import'


class Pusher
  attr_reader :space_guid
  attr_reader :service_prompts

  def initialize
    cf_config = JSON.parse(File.read("/Users/pivotal/.cf/config.json"))
    @space_guid = cf_config["SpaceFields"]["Guid"]
    @service_prompts = []
    super
  end

  def cold_push
    app_config = load_app_config
    create_services
    create_apps_and_bind_services(app_config)
    write_manifest(app_config)
    push_all_the_things
  end

  def get_binding
    binding
  end

  private
  attr_writer :space_guid

  def push_all_the_things
    say("Pushing the bits...")
    system("cf push -f manifest.yml")
  end

  def write_manifest(app_config)
    File.open('manifest.yml', 'w') {|f| f.write app_config.to_yaml }
  end

  def create_apps_and_bind_services(app_config)
    app_config["applications"].map do |app|
      say("Creating #{app["name"]}...")
      `cf curl "/v2/apps?async=true" -X POST -d '{"name":"#{app["name"]}","space_guid":"#{space_guid}"}'`
      @service_prompts.each do |service_prompt|
        say("Binding services...")
        `cf bind-service #{app["name"]} #{service_prompt.service_instance_name}`
      end
    end
  end

  def create_services
    service_offerings = get_list_of_services if service_prompts.any?
    service_prompts.each do |p|
      service_plan_selection = nil
      service_offering_selection = nil
      choose do |service_offering_menu|
        service_offering_menu.header = p.prompt
        service_offering_menu.prompt = "Pick a service:"

        service_offerings.each do |service_offering|
          service_offering_menu.choice(service_offering[:label]) do
            service_offering_selection = service_offering[:label]
            service_plan_selection = choose do |service_plan_menu|
              service_plan_menu.prompt = "Pick a plan:"

              service_offering[:plans].each do |service_plan|
                service_plan_menu.choice("#{service_plan[:name]}: #{service_plan[:description]}") do
                  service_plan_selection = service_plan[:name]
                end
              end
            end

          end
        end
      end
      system("cf create-service #{service_offering_selection} #{service_plan_selection} #{p.service_instance_name}")
    end

  end

  def get_list_of_services
    say "Getting the list of available services..."
    service_json = JSON.parse(`cf curl "/v2/spaces/#{space_guid}/services?inline-relations-depth=1"`)
    return service_json["resources"].map do |service|
      {
        label: service["entity"]["label"],
        provider: service["entity"]["provider"],
        plans: service["entity"]["service_plans"].map do |plan|
          {
            name: plan["entity"]["name"],
            description: plan["entity"]["description"],
          }
        end
      }
    end
  end

  def load_app_config
    YAML.load(ERB.new(File.read("cf_cold_push.yml.erb")).result(self.instance_eval { binding }))
  end

  def prompt(type, prompt = nil, default = nil)
    if type == :boolean
      agree(prompt)
    else
      if default
        ask(prompt, type) { |q| q.default = default if default }
      else
        ask(prompt, type)
      end
    end
  end

  def service_prompt(service_instance_name, prompt, optional = false)
    service_prompts << ServicePrompt.new(service_instance_name, prompt, optional)
  end
end

ServicePrompt = Struct.new(:service_instance_name, :prompt, :optional)

Pusher.new.cold_push
