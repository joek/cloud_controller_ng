require 'spec_helper'
require 'rspec_api_documentation/dsl'
require 'cgi'

resource 'Events', type: [:api, :legacy_api] do
  DOCUMENTED_EVENT_TYPES = %w(
    app.crash
    audit.app.start
    audit.app.stop
    audit.app.update
    audit.app.create
    audit.app.delete-request
    audit.app.ssh-authorized
    audit.app.ssh-unauthorized
    audit.space.create
    audit.space.update
    audit.space.delete-request
    audit.service_broker.create
    audit.service_broker.update
    audit.service_broker.delete
    audit.service.create
    audit.service.update
    audit.service.delete
    audit.service_plan.create
    audit.service_plan.update
    audit.service_plan.delete
    audit.service_plan_visibility.create
    audit.service_plan_visibility.update
    audit.service_plan_visibility.delete
    audit.service_dashboard_client.create
    audit.service_dashboard_client.delete
    audit.service_instance.create
    audit.service_instance.update
    audit.service_instance.delete
    audit.user_provided_service_instance.create
    audit.user_provided_service_instance.update
    audit.user_provided_service_instance.delete
    audit.service_binding.create
    audit.service_binding.delete
  )
  let(:admin_auth_header) { admin_headers['HTTP_AUTHORIZATION'] }
  authenticated_request

  before do
    3.times do
      VCAP::CloudController::Event.make
    end
  end

  let(:guid) { VCAP::CloudController::Event.first.guid }

  field :guid, 'The guid of the event.', required: false
  field :type, 'The type of the event.', required: false, readonly: true, valid_values: DOCUMENTED_EVENT_TYPES, example_values: %w(app.crash audit.app.update)
  field :actor, 'The GUID of the actor.', required: false, readonly: true
  field :actor_type, 'The actor type.', required: false, readonly: true, example_values: %w(user app)
  field :actor_name, 'The name of the actor.', required: false, readonly: true
  field :actee, 'The GUID of the actee.', required: false, readonly: true
  field :actee_type, 'The actee type.', required: false, readonly: true, example_values: %w(space app)
  field :actee_name, 'The name of the actee.', required: false, readonly: true
  field :timestamp, 'The event creation time.', required: false, readonly: true
  field :metadata, 'The additional information about event.', required: false, readonly: true, default: {}
  field :space_guid, 'The guid of the associated space.', required: false, readonly: true
  field :organization_guid, 'The guid of the associated organization.', required: false, readonly: true

  standard_model_list(:event, VCAP::CloudController::EventsController)
  standard_model_get(:event)

  get '/v2/events' do
    standard_list_parameters VCAP::CloudController::EventsController

    let(:test_app) { VCAP::CloudController::App.make }
    let(:test_user) { VCAP::CloudController::User.make }
    let(:test_user_email) { 'user@example.com' }
    let(:test_space) { VCAP::CloudController::Space.make }
    let(:test_organization) { VCAP::CloudController::Organization.make }

    let(:test_broker) { VCAP::CloudController::ServiceBroker.make }
    let(:test_service) { VCAP::CloudController::Service.make(service_broker: test_broker) }
    let(:test_plan) { VCAP::CloudController::ServicePlan.make(service: test_service) }
    let(:test_plan_visibility) do
      VCAP::CloudController::ServicePlanVisibility.make(organization_guid: test_organization.guid, service_plan_guid: test_plan.guid)
    end

    let(:app_request) do
      {
        'name' => 'new',
        'instances' => 1,
        'memory' => 84,
        'state' => 'STOPPED',
        'environment_json' => { 'super' => 'secret' }
      }
    end
    let(:space_request) do
      {
        'name' => 'outer space'
      }
    end
    let(:droplet_exited_payload) do
      {
        'instance' => 0,
        'index' => 1,
        'exit_status' => '1',
        'exit_description' => 'out of memory',
        'reason' => 'crashed'
      }
    end
    let(:expected_app_request) do
      expected_request = app_request
      expected_request['environment_json'] = 'PRIVATE DATA HIDDEN'
      expected_request
    end

    let(:app_event_repository) do
      VCAP::CloudController::Repositories::Runtime::AppEventRepository.new
    end

    let(:space_event_repository) do
      VCAP::CloudController::Repositories::Runtime::SpaceEventRepository.new
    end

    let(:service_event_repository) do
      VCAP::CloudController::Repositories::Services::EventRepository.new(user: test_user, user_email: test_user_email)
    end

    example 'List App Create Events' do
      app_event_repository.record_app_create(test_app, test_app.space, test_user.guid, test_user_email, app_request)

      client.get '/v2/events?q=type:audit.app.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'app',
                               actee: test_app.guid,
                               actee_name: test_app.name,
                               space_guid: test_app.space.guid,
                               metadata: { 'request' => expected_app_request }
    end

    example 'List App Start Events' do
      app_event_repository.record_app_start(test_app, test_user.guid, test_user_email)

      client.get '/v2/events?q=type:audit.app.start', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'app',
                               actee: test_app.guid,
                               actee_name: test_app.name,
                               space_guid: test_app.space.guid,
                               metadata: {}
    end

    example 'List App Stop Events' do
      app_event_repository.record_app_stop(test_app, test_user.guid, test_user_email)

      client.get '/v2/events?q=type:audit.app.stop', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                              actor_type: 'user',
                              actor: test_user.guid,
                              actor_name: test_user_email,
                              actee_type: 'app',
                              actee: test_app.guid,
                              actee_name: test_app.name,
                              space_guid: test_app.space.guid,
                              metadata: {}
    end

    example 'List App Exited Events' do
      app_event_repository.create_app_exit_event(test_app, droplet_exited_payload)

      client.get '/v2/events?q=type:app.crash', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'app',
                               actor: test_app.guid,
                               actor_name: test_app.name,
                               actee_type: 'app',
                               actee: test_app.guid,
                               actee_name: test_app.name,
                               space_guid: test_app.space.guid,
                               metadata: droplet_exited_payload
    end

    example 'List App Update Events' do
      app_event_repository.record_app_update(test_app, test_app.space, test_user.guid, test_user_email, app_request)

      client.get '/v2/events?q=type:audit.app.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'app',
                               actee: test_app.guid,
                               actee_name: test_app.name,
                               space_guid: test_app.space.guid,
                               metadata: {
                                 'request' => expected_app_request,
                               }
    end

    example 'List App Delete Events' do
      app_event_repository.record_app_delete_request(test_app, test_app.space, test_user.guid, test_user_email, false)

      client.get '/v2/events?q=type:audit.app.delete-request', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'app',
                               actee: test_app.guid,
                               actee_name: test_app.name,
                               space_guid: test_app.space.guid,
                               metadata: { 'request' => { 'recursive' => false } }
    end

    example 'List events associated with an App since January 1, 2014' do
      app_event_repository.record_app_create(test_app, test_app.space, test_user.guid, test_user_email, app_request)
      app_event_repository.record_app_update(test_app, test_app.space, test_user.guid, test_user_email, app_request)
      app_event_repository.record_app_delete_request(test_app, test_app.space, test_user.guid, test_user_email, false)

      client.get "/v2/events?q=actee:#{test_app.guid}&q=#{CGI.escape('timestamp>2014-01-01 00:00:00-04:00')}", {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'app',
                               actee: test_app.guid,
                               actee_name: test_app.name,
                               space_guid: test_app.space.guid,
                               metadata: { 'request' => expected_app_request }
    end

    example 'List Space Create Events' do
      space_event_repository.record_space_create(test_space, test_user, test_user_email, space_request)

      client.get '/v2/events?q=type:audit.space.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'space',
                               actee: test_space.guid,
                               actee_name: test_space.name,
                               space_guid: test_space.guid,
                               metadata: { 'request' => space_request }
    end

    example 'List Space Update Events' do
      space_event_repository.record_space_update(test_space, test_user, test_user_email, space_request)

      client.get '/v2/events?q=type:audit.space.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee: test_space.guid,
                               actee_type: 'space',
                               actee_name: test_space.name,
                               space_guid: test_space.guid,
                               metadata: { 'request' => space_request }
    end

    example 'List Space Delete Events' do
      space_event_repository.record_space_delete_request(test_space, test_user, test_user_email, true)

      client.get '/v2/events?q=type:audit.space.delete-request', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'space',
                               actee: test_space.guid,
                               actee_name: test_space.name,
                               space_guid: test_space.guid,
                               metadata: { 'request' => { 'recursive' => true } }
    end

    example 'List Service Dashboard Client Create Events' do
      client_attrs = {
        'id' => 'client_id',
        'secret' => 'secret',
        'redirect_uri' => 'example.com/redirect'
      }

      VCAP::CloudController::ServiceDashboardClient.new(
        uaa_id: client_attrs['id'],
        service_broker: VCAP::CloudController::ServiceBroker.make
      ).save

      service_event_repository.record_service_dashboard_client_event(:create, client_attrs, test_broker)

      client.get '/v2/events?q=type:audit.service_dashboard_client.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service_dashboard_client',
                               actee: client_attrs['id'],
                               actee_name: client_attrs['id'],
                               space_guid: '',
                               metadata: {
                                    'secret' => '[REDACTED]',
                                    'redirect_uri' => client_attrs['redirect_uri']
                               }
    end

    example 'List Service Dashboard Client Delete Events' do
      client_attrs = {
        'id' => 'client_id'
      }

      VCAP::CloudController::ServiceDashboardClient.new(
        uaa_id: client_attrs['id'],
        service_broker: VCAP::CloudController::ServiceBroker.make
      ).save

      service_event_repository.record_service_dashboard_client_event(:delete, client_attrs, test_broker)

      client.get '/v2/events?q=type:audit.service_dashboard_client.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service_dashboard_client',
                               actee: client_attrs['id'],
                               actee_name: client_attrs['id'],
                               space_guid: '',
                               metadata: {}
    end

    example 'List Service Plan Create Events' do
      new_plan = VCAP::CloudController::ServicePlan.new(
        guid: 'guid',
        name: 'plan-name',
        service: test_service,
        description: 'A plan',
        unique_id: 'guid',
        free: true,
        public: true,
        active: true
      )
      service_event_repository.with_service_plan_event(new_plan) do
        new_plan.save
      end

      client.get '/v2/events?q=type:audit.service_plan.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service_plan',
                               actee: new_plan.guid,
                               actee_name: new_plan.name,
                               space_guid: '',
                               metadata: {
                                 'name' => new_plan.name,
                                 'free' => new_plan.free,
                                 'description' => new_plan.description,
                                 'service_guid' => new_plan.service.guid,
                                 'extra' => new_plan.extra,
                                 'unique_id' => new_plan.unique_id,
                                 'public' => new_plan.public,
                                 'active' => new_plan.active
                               }
    end

    example 'List Service Plan Update Events' do
      test_plan.name = 'new name'
      service_event_repository.with_service_plan_event(test_plan) do
        test_plan.save
      end

      client.get '/v2/events?q=type:audit.service_plan.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service_plan',
                               actee: test_plan.guid,
                               actee_name: test_plan.name,
                               space_guid: '',
                               metadata: { 'name' => 'new name' }
    end

    example 'List Service Plan Delete Events' do
      service_event_repository.record_service_plan_event(:delete, test_plan)

      client.get '/v2/events?q=type:audit.service_plan.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service_plan',
                               actee: test_plan.guid,
                               actee_name: test_plan.name,
                               space_guid: '',
                               metadata: {}
    end

    example 'List Service Plan Visibility Create Events' do
      params = {
        'service_plan_guid' => test_plan_visibility.service_plan_guid,
        'organization_guid' => test_plan_visibility.organization_guid
      }
      service_event_repository.record_service_plan_visibility_event(:create, test_plan_visibility, params)

      client.get '/v2/events?q=type:audit.service_plan_visibility.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_plan_visibility',
                               actee: test_plan_visibility.guid,
                               actee_name: '',
                               space_guid: '',
                               organization_guid: test_plan_visibility.organization_guid,
                               metadata: {
                                 'request' => params
                               }
    end

    example 'List Service Plan Visibility Update Events' do
      params = {
        'service_plan_guid' => test_plan_visibility.service_plan_guid,
        'organization_guid' => test_plan_visibility.organization_guid
      }
      service_event_repository.record_service_plan_visibility_event(:update, test_plan_visibility, params)

      client.get '/v2/events?q=type:audit.service_plan_visibility.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_plan_visibility',
                               actee: test_plan_visibility.guid,
                               actee_name: '',
                               space_guid: '',
                               organization_guid: test_plan_visibility.organization_guid,
                               metadata: {
                                 'request' => params
                               }
    end

    example 'List Service Plan Visibility Delete Events' do
      service_event_repository.record_service_plan_visibility_event(:delete, test_plan_visibility, {})

      client.get '/v2/events?q=type:audit.service_plan_visibility.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_plan_visibility',
                               actee: test_plan_visibility.guid,
                               actee_name: '',
                               space_guid: '',
                               organization_guid: test_plan_visibility.organization_guid,
                               metadata: { 'request' => {} }
    end

    example 'List Service Create Events' do
      new_service = VCAP::CloudController::Service.new(
        guid: 'guid',
        label: 'label',
        description: 'BOOOO',
        bindable: true,
        service_broker: test_broker,
        plan_updateable: false,
        active: true,
      )
      service_event_repository.with_service_event(new_service) do
        new_service.save
      end

      client.get '/v2/events?q=type:audit.service.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service',
                               actee: new_service.guid,
                               actee_name: new_service.label,
                               space_guid: '',
                               metadata: {
                                 'service_broker_guid' => new_service.service_broker.guid,
                                 'unique_id' => new_service.broker_provided_id,
                                 'provider' => new_service.provider,
                                 'url' => new_service.url,
                                 'version' => new_service.version,
                                 'info_url' => new_service.info_url,
                                 'bindable' => new_service.bindable,
                                 'long_description' => new_service.long_description,
                                 'documentation_url' => new_service.documentation_url,
                                 'label' => new_service.label,
                                 'description' => new_service.description,
                                 'tags' => new_service.tags,
                                 'extra' => new_service.extra,
                                 'active' => new_service.active,
                                 'requires' => new_service.requires,
                                 'plan_updateable' => new_service.plan_updateable,
                               }
    end

    example 'List Service Update Events' do
      test_service.label = 'new label'
      service_event_repository.with_service_event(test_service) do
        test_service.save
      end

      client.get '/v2/events?q=type:audit.service.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service',
                               actee: test_service.guid,
                               actee_name: test_service.label,
                               space_guid: '',
                               metadata: { 'label' => 'new label' }
    end

    example 'List Service Delete Events' do
      service_event_repository.record_service_event(:delete, test_service)

      client.get '/v2/events?q=type:audit.service.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'service_broker',
                               actor: test_broker.guid,
                               actor_name: test_broker.name,
                               actee_type: 'service',
                               actee: test_service.guid,
                               actee_name: test_service.label,
                               space_guid: '',
                               metadata: {}
    end

    example 'List Service Broker Create Events' do
      params = {
        name: 'pancake broker',
        broker_url: 'http://www.pancakes.com',
        auth_username: 'panda',
        auth_password: 'password'
      }
      broker = VCAP::CloudController::ServiceBroker.make(params)
      service_event_repository.record_broker_event(:create, broker, params)

      client.get '/v2/events?q=type:audit.service_broker.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_broker',
                               actee: broker.guid,
                               actee_name: 'pancake broker',
                               space_guid: '',
                               metadata: {
                                 'request' => {
                                   'name' => 'pancake broker',
                                   'broker_url' => 'http://www.pancakes.com',
                                   'auth_username' => 'panda',
                                   'auth_password' => '[REDACTED]'
                                 }
                               }
    end

    example 'List Service Broker Update Events' do
      params = {
        broker_url: 'http://www.pancakes.com',
        auth_password: 'password'
      }
      broker = VCAP::CloudController::ServiceBroker.make
      service_event_repository.record_broker_event(:update, broker, params)

      client.get '/v2/events?q=type:audit.service_broker.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_broker',
                               actee: broker.guid,
                               actee_name: broker.name,
                               space_guid: '',
                               metadata: {
                                 'request' => {
                                   'broker_url' => 'http://www.pancakes.com',
                                   'auth_password' => '[REDACTED]'
                                 }
                               }
    end

    example 'List Service Broker Delete Events' do
      broker = VCAP::CloudController::ServiceBroker.make
      service_event_repository.record_broker_event(:delete, broker, {})

      client.get '/v2/events?q=type:audit.service_broker.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_broker',
                               actee: broker.guid,
                               actee_name: broker.name,
                               space_guid: '',
                               metadata: { 'request' => {} }
    end

    example 'List Service Instance Create Events' do
      instance = VCAP::CloudController::ManagedServiceInstance.make
      service_event_repository.record_service_instance_event(:create, instance, {
        'name' => instance.name,
        'service_plan_guid' => instance.service_plan.guid,
        'space_guid' => instance.space_guid,
      })

      client.get '/v2/events?q=type:audit.service_instance.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_instance',
                               actee: instance.guid,
                               actee_name: instance.name,
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {
                                   'name' => instance.name,
                                   'service_plan_guid' => instance.service_plan.guid,
                                   'space_guid' => instance.space_guid,
                                 }
                               }
    end

    example 'List Service Instance Update Events' do
      instance = VCAP::CloudController::ManagedServiceInstance.make
      service_event_repository.record_service_instance_event(:update, instance, {
        'service_plan_guid' => instance.service_plan.guid,
      })

      client.get '/v2/events?q=type:audit.service_instance.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_instance',
                               actee: instance.guid,
                               actee_name: instance.name,
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {
                                   'service_plan_guid' => instance.service_plan.guid,
                                 }
                               }
    end

    example 'List Service Instance Delete Events' do
      instance = VCAP::CloudController::ManagedServiceInstance.make
      service_event_repository.record_service_instance_event(:delete, instance, {})

      client.get '/v2/events?q=type:audit.service_instance.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_instance',
                               actee: instance.guid,
                               actee_name: instance.name,
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {}
                               }
    end

    example 'List User Provided Service Instance Create Events' do
      instance = VCAP::CloudController::UserProvidedServiceInstance.make
      service_event_repository.record_user_provided_service_instance_event(:create, instance, {
        'name' => instance.name,
        'space_guid' => instance.space_guid,
      })

      client.get '/v2/events?q=type:audit.user_provided_service_instance.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'user_provided_service_instance',
                               actee: instance.guid,
                               actee_name: instance.name,
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {
                                   'name' => instance.name,
                                   'space_guid' => instance.space_guid,
                                 }
                               }
    end

    example 'List User Provided Service Instance Update Events' do
      instance = VCAP::CloudController::UserProvidedServiceInstance.make
      service_event_repository.record_user_provided_service_instance_event(:update, instance, {
        'credentials' => { 'username' => 'myUser' }
      })

      client.get '/v2/events?q=type:audit.user_provided_service_instance.update', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'user_provided_service_instance',
                               actee: instance.guid,
                               actee_name: instance.name,
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {
                                   'credentials' => '[REDACTED]'
                                 }
                               }
    end

    example 'List User Provided Service Instance Delete Events' do
      instance = VCAP::CloudController::UserProvidedServiceInstance.make
      service_event_repository.record_user_provided_service_instance_event(:delete, instance, {})

      client.get '/v2/events?q=type:audit.user_provided_service_instance.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'user_provided_service_instance',
                               actee: instance.guid,
                               actee_name: instance.name,
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {}
                               }
    end

    example 'List Service Binding Create Events' do
      space = VCAP::CloudController::Space.make
      instance = VCAP::CloudController::ManagedServiceInstance.make(space: space)
      app = VCAP::CloudController::App.make(space: space)
      service_binding = VCAP::CloudController::ServiceBinding.make(service_instance: instance, app: app)

      service_event_repository.record_service_binding_event(:create, service_binding)

      client.get '/v2/events?q=type:audit.service_binding.create', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_binding',
                               actee: service_binding.guid,
                               actee_name: '',
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {
                                   'service_instance_guid' => instance.guid,
                                   'app_guid' => app.guid,
                                 }
                               }
    end

    example 'List Service Binding Delete Events' do
      space = VCAP::CloudController::Space.make
      instance = VCAP::CloudController::ManagedServiceInstance.make(space: space)
      app = VCAP::CloudController::App.make(space: space)
      service_binding = VCAP::CloudController::ServiceBinding.make(service_instance: instance, app: app)

      service_event_repository.record_service_binding_event(:delete, service_binding)

      client.get '/v2/events?q=type:audit.service_binding.delete', {}, headers
      expect(status).to eq(200)
      standard_entity_response parsed_response['resources'][0], :event,
                               actor_type: 'user',
                               actor: test_user.guid,
                               actor_name: test_user_email,
                               actee_type: 'service_binding',
                               actee: service_binding.guid,
                               actee_name: '',
                               space_guid: instance.space_guid,
                               metadata: {
                                 'request' => {}
                               }
    end
  end
end
