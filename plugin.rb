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

require_relative "lib/my_plugin_module/engine"

after_initialize do
  # --- 1. THE BOUNCER (Guardian) ---
  module ::DiscourseTagGatingGuardianExtension
    def can_see_topic?(topic, *args, **kwargs)
      return false unless super

      # tags_nm is only populated on list queries; fall back to a DB check
      tag_names = topic.tags_nm.presence || topic.tags.pluck(:name)
      
      if tag_names.include?("nsfw")
        return user.present? && user.user_fields["7"] == "true"
      end

      true
    end
  end

  # --- 2. THE FILTER (Post Scope) ---
  module FilterNSFW
    def secured(guardian = nil, *args, **kwargs)
      scope = super
      
      # Discourse passes a Guardian object, not a user directly
      current_user = guardian.respond_to?(:user) ? guardian.user : nil
      
      # Staff bypass restrictions
      return scope if current_user&.staff?
      
      has_nsfw_access = current_user.present? && current_user.user_fields["7"] == "true"
      
      unless has_nsfw_access
        nsfw_tag_subquery = Tag.where(name: "nsfw").select(:id)
        blocked_topic_ids = TopicTag.where(tag_id: nsfw_tag_subquery).select(:topic_id)
        scope = scope.where.not(topic_id: blocked_topic_ids)
      end
      
      scope
    end
  end

  Post.singleton_class.prepend FilterNSFW
  Guardian.prepend(::DiscourseTagGatingGuardianExtension)
end
