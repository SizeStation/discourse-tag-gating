# frozen_string_literal: true

# name: discourse-tag-gating
# about: A plugin to gate access to topics based on tags
# meta_topic_id: TODO
# version: 0.0.2
# authors: SkyDev125
# url: https://github.com/SizeStation/discourse-tag-gating
# required_version: 2.7.0

enabled_site_setting :tag_gating_enabled

module ::MyPluginModule
  PLUGIN_NAME = "tag-gating"
end

module ::DiscourseTagGating
  def self.has_access?(user)
    return false if user.blank?
    return true if user.staff?
    Rails.logger.debug("Checking tag gating access for user #{user.id} with fields #{user.user_fields}, looking at field #{user.user_fields[SiteSetting.tag_gating_user_field_id.to_s]}")
    Rails.logger.debug("Site settings: tag_gating_user_field_id=#{SiteSetting.tag_gating_user_field_id}, tag_gating_user_field_id=#{SiteSetting.tag_gating_user_field_id.to_s}, tag_gating_user_field_logic=#{SiteSetting.tag_gating_user_field_logic}")
    expected = SiteSetting.tag_gating_user_field_logic ? "true" : "false"
    RAILS.logger.debug("Access result: #{expected}")
    user.user_fields[SiteSetting.tag_gating_user_field_id.to_s] == expected
  end

  def self.topic_has_tag?(topic)
    if topic.association(:tags).loaded?
      topic.tags.map(&:name)
    else
      topic.tags.pluck(:name)
    end.include?(SiteSetting.tag_gating_tag_name)
  end

  def self.blocked_topic_ids_for(user)
    tag_id = Tag.where(name: SiteSetting.tag_gating_tag_name).select(:id)
    topic_ids = TopicTag.where(tag_id: tag_id).select(:topic_id)
    Topic.where(id: topic_ids).where.not(user_id: user&.id).select(:id)
  end
end

require_relative "lib/my_plugin_module/engine"

after_initialize do
  # --- 1. THE BOUNCER (Guardian) ---
  module ::DiscourseTagGatingGuardianExtension
    def can_see_topic?(topic, *args, **kwargs)
      return super unless SiteSetting.tag_gating_enabled
      return false unless super
      return true if topic.user_id == user&.id

      if DiscourseTagGating.topic_has_tag?(topic) && !DiscourseTagGating.has_access?(user)
        raise Discourse::InvalidAccess.new(
                "access_required",
                topic,
                custom_message: "discourse_tag_gating.access_required",
              )
      end
      true
    end
  end

  # --- 2. THE FILTER (Post Scope) ---
  module FilterGatedPosts
    def secured(guardian = nil, *args, **kwargs)
      results = super
      return results unless SiteSetting.tag_gating_enabled
      user = guardian.respond_to?(:user) ? guardian.user : nil

      unless DiscourseTagGating.has_access?(user)
        results = results.where.not(topic_id: DiscourseTagGating.blocked_topic_ids_for(user))
      end

      results
    end
  end

  # --- 3. THE LIST FILTER (TopicQuery) ---
  module FilterGatedTopics
    def default_results(options = {})
      results = super
      return results unless SiteSetting.tag_gating_enabled
      unless DiscourseTagGating.has_access?(@user)
        results = results.where.not(id: DiscourseTagGating.blocked_topic_ids_for(@user))
      end

      results
    end
  end

  # --- 4. THE SEARCH FILTER ---
  Search.advanced_filter(/.*/) do |posts, match|
    next posts unless SiteSetting.tag_gating_enabled
    unless DiscourseTagGating.has_access?(@guardian&.user)
      posts = posts.where.not(topic_id: DiscourseTagGating.blocked_topic_ids_for(@guardian&.user))
    end

    posts
  end

  # --- 5. THE FEATURED TOPICS FILTER (CategoryList) ---
  module FilterGatedCategoryList
    def load_topics
      super
      return unless SiteSetting.tag_gating_enabled
      return unless @all_topics

      unless DiscourseTagGating.has_access?(@guardian&.user)
        user_id = @guardian&.user&.id
        featured_ids = @all_topics.map(&:id)
        tag_id = Tag.where(name: SiteSetting.tag_gating_tag_name).select(:id)
        tagged_featured_ids =
          TopicTag.where(topic_id: featured_ids, tag_id: tag_id).pluck(:topic_id).to_set
        blocked_ids =
          @all_topics
            .select { |t| tagged_featured_ids.include?(t.id) && t.user_id != user_id }
            .map(&:id)
            .to_set

        # Filter both structures
        @all_topics.reject! { |t| blocked_ids.include?(t.id) }
        @topics_by_category_id.each do |cat_id, topic_ids|
          @topics_by_category_id[cat_id] = topic_ids.reject { |tid| blocked_ids.include?(tid) }
        end
      end
    end
  end

  CategoryList.prepend FilterGatedCategoryList
  TopicQuery.prepend FilterGatedTopics
  Post.singleton_class.prepend FilterGatedPosts
  Guardian.prepend(::DiscourseTagGatingGuardianExtension)
end
