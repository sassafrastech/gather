# frozen_string_literal: true

module Work
  # Calculates data for topline status message.
  class Topline
    attr_accessor :period, :user

    delegate :quota_type, to: :period

    def initialize(period:, user:)
      self.period = period
      self.user = user
    end

    def summary
      return @summary if defined?(@summary)
      return (@summary = nil) if !period.open? || period.quota_none? || share_for(:self).zero?
      @summary = {}
      @summary[:self] = obligations_for(:self)
      if period.quota_by_person?
        @summary[:done] = all_ok?(@summary[:self])
      else
        @summary[:household] = obligations_for(:household)
        @summary[:done] = all_ok?(@summary[:household])

        # If household is all set, this overrides all self obligations to be ok.
        @summary[:self].each { |o| o[:ok] = true } if @summary[:done]
      end
      @summary
    end

    private

    def obligations_for(who)
      buckets.map do |bucket|
        hours = assigned_hours_for(who, bucket)
        ttl = quota_for(who, bucket)
        ok = round_next_half(hours) >= round_next_half(ttl)
        {bucket: bucket, got: hours, ttl: ttl, ok: ok}
      end
    end

    def all_ok?(obligation)
      obligation.all? { |o| o[:ok] }
    end

    def quota_for(who, bucket)
      (bucket == regular ? period.quota : bucket.hours) * share_for(who)
    end

    def assigned_hours_for(who, bucket)
      scope = Assignment.where(user: users(who)).includes(shift: :job)
      if bucket == regular
        scope.merge(Job.fixed_slot).sum("work_jobs.hours")
      else
        # For full community jobs, shift hours are different from job hours, so SQL sum won't work.
        scope.where("work_shifts.job_id": bucket.id).to_a.sum(&:shift_hours)
      end
    end

    def share_for(who)
      Share.for_period(period).where(user: users(who)).sum(:portion)
    end

    def users(who)
      who == :household ? user.household.users : [user]
    end

    def buckets
      @buckets ||= [regular] + Job.full_community.by_title.in_period(period)
    end

    def round_next_half(num)
      (num * 2).ceil.to_f / 2
    end

    # Duck type for job.
    def regular
      @regular ||= OpenStruct.new(title: I18n.t("work.topline.regular"))
    end
  end
end