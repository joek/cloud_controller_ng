require 'spec_helper'
require 'actions/service_instance_create'

module VCAP::CloudController
  describe ServiceInstanceCreate do
    let(:event_repository) { double(:event_repository, record_service_instance_event: nil) }
    let(:logger) { double(:logger) }
    subject(:create_action) { ServiceInstanceCreate.new(event_repository, logger) }

    describe '#create' do
      let(:space) { Space.make }
      let(:service_plan) { ServicePlan.make }
      let(:request_attrs) do
        {
            'space_guid' => space.guid,
            'service_plan_guid' => service_plan.guid,
            'name' => 'my-instance'
        }
      end

      before do
        stub_provision(service_plan.service.service_broker)
      end

      it 'creates the service instance with the requested params' do
        expect {
          create_action.create(request_attrs, false)
        }.to change { ServiceInstance.count }.from(0).to(1)
      end

      it 'creates an audit event' do
        create_action.create(request_attrs, false)
        expect(event_repository).to have_received(:record_service_instance_event).with(:create, an_instance_of(ManagedServiceInstance), request_attrs)
      end

      context 'when there are arbitrary params' do
        let(:parameters) { { 'some-param' => 'some-value' } }
        let(:request_attrs) do
          {
              'space_guid' => space.guid,
              'service_plan_guid' => service_plan.guid,
              'name' => 'my-instance',
              'parameters' => parameters
          }
        end

        it 'passes the params to the client' do
          create_action.create(request_attrs, false)
          expect(a_request(:put, /.*/).with(body: hash_including({ parameters: parameters }))).to have_been_made
        end
      end

      context 'with accepts_incomplete' do
        before do
          stub_provision(service_plan.service.service_broker, accepts_incomplete: true, status: 202)
        end

        it 'enqueues a fetch job' do
          expect {
            create_action.create(request_attrs, true)
          }.to change { Delayed::Job.count }.from(0).to(1)

          expect(Delayed::Job.first).to be_a_fully_wrapped_job_of Jobs::Services::ServiceInstanceStateFetch
        end

        it 'does not log an audit event' do
          create_action.create(request_attrs, true)
          expect(event_repository).not_to have_received(:record_service_instance_event)
        end
      end

      context 'when the instance fails to save to the db' do
        let(:mock_orphan_mitigator) { double(:mock_orphan_mitigator, attempt_deprovision_instance: nil) }
        before do
          allow(SynchronousOrphanMitigate).to receive(:new).and_return(mock_orphan_mitigator)
          allow_any_instance_of(ManagedServiceInstance).to receive(:save).and_raise
        end

        it 'attempts synchronous orphan mitigation' do
          expect {
            create_action.create(request_attrs, false)
          }.to raise_error
          expect(mock_orphan_mitigator).to have_received(:attempt_deprovision_instance)
        end
      end
    end
  end
end
