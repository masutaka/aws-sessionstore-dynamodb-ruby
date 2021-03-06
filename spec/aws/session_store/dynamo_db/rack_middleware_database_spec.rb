# Copyright 2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'spec_helper'

module AWS
  module SessionStore
    module DynamoDB
      describe RackMiddleware do
        include Rack::Test::Methods

        instance_exec(&ConstantHelpers)

        before do
          @options = { :secret_key => 'watermelon_cherries' }
        end

        # Table options for client
        def table_opts(sid)
          {
            :table_name => Configuration::DEFAULTS[:table_name],
            :key => { Configuration::DEFAULTS[:table_key] => { :s => sid } }
          }
        end

        # Attributes to be retrieved via client
        def attr_opts
          {
            :attributes_to_get => ["data", "created_at", "locked_at"],
            :consistent_read => true
          }
        end

        def extract_time(sid)
          options = table_opts(sid).merge(attr_opts)
          Time.at((client.get_item(options)[:item]["created_at"][:n]).to_f)
        end

        let(:base_app) { MultiplierApplication.new }
        let(:app) { RackMiddleware.new(base_app, @options) }
        let(:config) { Configuration.new }
        let(:client) { config.dynamo_db_client }

        context "Testing best case session storage", :integration => true do
          it "stores session data in session object" do
            get "/"
            last_request.session[:multiplier].should eq(1)
          end

          it "creates a new HTTP cookie when Cookie not supplied" do
            get "/"
            last_response.body.should eq('All good!')
            last_response['Set-Cookie'].should be_true
          end

          it "does not rewrite Cookie if cookie previously/accuarately set" do
            get "/"
            last_response['Set-Cookie'].should_not be_nil


            get "/"
            last_response['Set-Cookie'].should be_nil
          end

          it "does not set cookie when defer option is specifed" do
            @options[:defer] = true
            get "/"
            last_response['Set-Cookie'].should be_nil
          end

          it "creates new sessopm with false/nonexistant http-cookie id" do
            get "/", {}, invalid_cookie.merge(invalid_session_data)
            last_response['Set-Cookie'].should_not eq("rack.session=ApplePieBlueberries")
            last_response['Set-Cookie'].should_not be_nil
          end

          it "expires after specified time and sets date for cookie to expire" do
            @options[:expire_after] = 1
            get "/"
            session_cookie = last_response['Set-Cookie']
            sleep(1.2)

            get "/"
            last_response['Set-Cookie'].should_not be_nil
            last_response['Set-Cookie'].should_not eq(session_cookie)
          end

          it "will not set a session cookie when defer is true" do
            @options[:defer] = true
            get "/"
            last_response['Set-Cookie'].should eq(nil)
          end

          it "adds the created at attribute for a new session" do
            get "/"
            last_request.env["dynamo_db.new_session"].should eq("true")
            sid = last_response['Set-Cookie'].split(/[;\=]/)[1]
            time = extract_time(sid)
            time.should be_within(2).of(Time.now)

            get "/"
            last_request.env['dynamo_db.new_session'].should be(nil)
          end

          it "releases pessimistic lock at finish of transaction" do
            @options[:enable_locking] = true
            get "/"
            last_request.env["dynamo_db.new_session"].should eq("true")
            sid = last_response['Set-Cookie'].split(/[;\=]/)[1]

            get "/"
            options = table_opts(sid).merge(attr_opts)
            client.get_item(options)[:item]["locked_at"].should be_nil
          end
        end
      end
    end
  end
end
