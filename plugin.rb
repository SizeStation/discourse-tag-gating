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
  add_to_class(:guardian, :can_see_topic?) do |topic|
    return false unless super(topic)

    # Use the optimized 'tags_nm' (names) array to avoid a DB hit
    is_nsfw = topic.tags_nm&.include?("nsfw")

    if is_nsfw
      # Access allowed ONLY if: User exists AND Field 7 is checked
      return user.present? && user.user_fields["7"] == "true"
    end

    true
  end

  # --- 2. THE FILTER (Post Scope) ---
  module FilterNSFW
    def secured(user, guardian)
      scope = super(user, guardian)

      # Staff usually bypass restrictions
      return scope if user&.staff?

      # Define access rule: User must exist AND have Field 7 checked
      has_nsfw_access = user.present? && user.user_fields["7"] == "true"

      # Unless they have specific access, apply the filter
      unless has_nsfw_access
        # 1. Find the ID of the restricted tag
        nsfw_tag_subquery = Tag.where(name: "nsfw").select(:id)

        # 2. Find all topics associated with that tag
        blocked_topic_ids = TopicTag.where(tag_id: nsfw_tag_subquery).select(:topic_id)

        # 3. Exclude posts belonging to those topics
        scope = scope.where.not(topic_id: blocked_topic_ids)
      end

      scope
    end
  end

  Post.singleton_class.prepend FilterNSFW
end
