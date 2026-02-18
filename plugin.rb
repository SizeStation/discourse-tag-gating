# frozen_string_literal: true

# name: discourse-tag-gating
# about: A plugin to gate access to topics based on tags
# meta_topic_id: TODO
# version: 0.0.1
# authors: SkyDev125
# url: https://github.com/SizeStation/discourse-tag-gating
# required_version: 2.7.0

enabled_site_setting :tag_gating_enabled

module ::MyPluginModule
  PLUGIN_NAME = "tag-gating"
end

module ::DiscourseTagGating
  def self.nsfw_access?(user)
    user.present? && user.user_fields[SiteSetting.tag_gating_user_field_id.to_s] == "true"
  end
end

require_relative "lib/my_plugin_module/engine"

after_initialize do
  # --- 1. THE BOUNCER (Guardian) ---
  module ::DiscourseTagGatingGuardianExtension
    def can_see_topic?(topic, *args, **kwargs)
      return super unless SiteSetting.tag_gating_enabled
      return false unless super

      # Use the already-loaded association if available, otherwise query
      tag_names =
        if topic.association(:tags).loaded?
          topic.tags.map(&:name)
        else
          topic.tags.pluck(:name)
        end

      return DiscourseTagGating.nsfw_access?(user) if tag_names.include?("nsfw")

      true
    end
  end

  # --- 2. THE FILTER (Post Scope) ---
  module FilterNSFW
    def secured(guardian = nil, *args, **kwargs)
      scope = super
      return scope unless SiteSetting.tag_gating_enabled

      # Discourse passes a Guardian object, not a user directly
      user = guardian.respond_to?(:user) ? guardian.user : nil

      # Staff bypass restrictions
      return scope if user&.staff?

      unless DiscourseTagGating.nsfw_access?(user)
        nsfw_tag_subquery = Tag.where(name: "nsfw").select(:id)
        blocked_topic_ids = TopicTag.where(tag_id: nsfw_tag_subquery).select(:topic_id)
        scope = scope.where.not(topic_id: blocked_topic_ids)
      end

      scope
    end
  end

  # --- 3. THE LIST FILTER (TopicQuery) ---
  module FilterNSFWTopics
    def default_results(options = {})
      results = super
      return results unless SiteSetting.tag_gating_enabled

      current_user = @user
      return results if current_user&.staff?

      unless DiscourseTagGating.nsfw_access?(current_user)
        nsfw_tag_subquery = Tag.where(name: "nsfw").select(:id)
        blocked_topic_ids = TopicTag.where(tag_id: nsfw_tag_subquery).select(:topic_id)
        results = results.where.not(id: blocked_topic_ids)
      end

      results
    end
  end

  TopicQuery.prepend FilterNSFWTopics
  Post.singleton_class.prepend FilterNSFW
  Guardian.prepend(::DiscourseTagGatingGuardianExtension)
end
