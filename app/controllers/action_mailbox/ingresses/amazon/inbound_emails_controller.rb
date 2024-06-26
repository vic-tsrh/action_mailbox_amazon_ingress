# frozen_string_literal: true

require 'action_mailbox_amazon_ingress/sns_notification'

module ActionMailbox
  # Ingests inbound emails from Amazon SES/SNS and confirms subscriptions.
  #
  # Subscription requests must provide the following parameters in a JSON body:
  # - +Message+: Notification content
  # - +MessagId+: Notification unique identifier
  # - +Timestamp+: iso8601 timestamp
  # - +TopicArn+: Topic identifier
  # - +Type+: Type of event ("Subscription")
  #
  # Inbound email events must provide the following parameters in a JSON body:
  # - +Message+: Notification content
  # - +MessagId+: Notification unique identifier
  # - +Timestamp+: iso8601 timestamp
  # - +SubscribeURL+: Topic identifier
  # - +TopicArn+: Topic identifier
  # - +Type+: Type of event ("SubscriptionConfirmation")
  #
  # All requests are authenticated by validating the provided AWS signature.
  #
  # Returns:
  #
  # - <tt>204 No Content</tt> if a request is successfully processed
  # - <tt>401 Unauthorized</tt> if a request does not contain a valid signature
  # - <tt>404 Not Found</tt> if the Amazon ingress has not been configured
  # - <tt>422 Unprocessable Entity</tt> if a request provides invalid parameters

  module Ingresses
    module Amazon
      class InboundEmailsController < ActionMailbox::BaseController
        before_action :verify_authenticity, :validate_topic, :confirm_subscription

        def create
          head :bad_request unless notification.message_content.present?

          ActionMailbox::InboundEmail.create_and_extract_message_id!(notification.message_content)
          head :no_content
        end

        private

        def verify_authenticity
          head :bad_request unless notification.present?
          head :unauthorized unless notification.verified?
        end

        def confirm_subscription
          return unless notification.type == 'SubscriptionConfirmation'
          return head :ok if notification.subscription_confirmed?

          Rails.logger.error('SNS subscription confirmation request rejected.')
          head :unprocessable_entity
        end

        def validate_topic
          return if valid_topics.include?(notification.topic)

          Rails.logger.warn("Ignoring unknown topic: #{topic}")
          head :unauthorized
        end

        def notification
          @notification ||= ActionMailboxAmazonIngress::SnsNotification.new(request.raw_post)
        end

        def topic
          @topic ||= notification.topic
        end

        def valid_topics
          ::Rails.configuration.action_mailbox.amazon.subscribed_topics
        end
      end
    end
  end
end
