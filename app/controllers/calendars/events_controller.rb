# frozen_string_literal: true

module Calendars
  # Main events controller.
  class EventsController < ApplicationController
    include Lensable

    decorates_assigned :event, :calendar, :calendars, :meal

    before_action -> { nav_context(:calendars, :events) }

    def index
      return render_json_event_list if request.xhr?

      calendar_scope = policy_scope(Node).in_community(current_community).active
      @calendars = calendar_scope.arrange(decorator: CalendarDecorator)
      if params[:calendar_id]
        @calendar = Calendar.find(params[:calendar_id])
        prep_single_calendar_index
      else
        prep_combined_index(calendar_scope)
      end
    end

    def show
      @event = Event.find(params[:id])
      authorize(@event)
      @calendar = @event.calendar
      @meal = @event.meal
    end

    def new
      if params[:calendar_id]
        render_form
      elsif writeable_calendars.any?
        render_choose_calendar_page
      else
        render_error_page(:forbidden)
      end
    end

    def edit
      @event = Event.find(params[:id])
      @event.origin_page = params[:origin_page]
      authorize(@event)
      @event.guidelines_ok = "1"
      prep_form_vars
    end

    def create
      @event = Event.new(creator: current_user)
      assign_calendar
      @event.assign_attributes(event_params)
      authorize(@event)
      if @event.save
        flash[:success] = "Event created successfully."
        redirect_to_event_in_context(@event)
      else
        prep_form_vars
        render(:new)
      end
    end

    def update
      @event = Event.find(params[:id])
      authorize(@event)
      return handle_xhr_update if request.xhr?
      if @event.update(event_params)
        flash[:success] = "Event updated successfully."
        redirect_to_event_in_context(@event)
      else
        prep_form_vars
        render(:edit)
      end
    end

    def destroy
      @event = Event.find(params[:id])
      @event.origin_page = params[:origin_page]
      authorize(@event)
      @event.destroy
      flash[:success] = "Event deleted successfully."
      redirect_to_event_in_context(@event)
    end

    protected

    # See def'n in ApplicationController for documentation.
    def community_for_route
      case params[:action]
      when "show"
        Event.find_by(id: params[:id]).try(:community)
      when "index"
        current_user.community
      end
    end

    private

    def prep_single_calendar_index
      # We use an unsaved sample event to authorize against.
      # We set kind to nil because we can't know the kind in advance. This object is also used
      # to fetch a RuleSet for use in showing other_communities warnings and fixed start/end times.
      # As such, only warnings and fixed time rules that don't specify a particular kind will be observed.
      # Kind-specific rules will be enforced through validation.
      @sample_event = Event.new(calendar: @calendar, creator: current_user, kind: nil)
      authorize(@sample_event)
      @can_create_event = policy(@sample_event).create?

      @rule_set = @sample_event.rule_set
      if @rule_set.access_level(current_user.community) == "read_only"
        flash.now[:notice] = "Only #{@calendar.community_name} residents may reserve this calendar."
      end
      @rule_set = RuleSetSerializer.new(@rule_set, creator_community: current_community)
      @other_communities = Community.where("id != ?", @calendar.community_id)

      @new_event_path = new_calendars_event_path(calendar_id: @calendar.id)
      @permalink = calendars_events_path(calendar_id: @calendar.id)
      # Feed path doesn't need calendar_id because the JS calendar view is responsible for inserting
      # whichever calendar ids the user selects, or the single ID in the case of single view.
      @feed_path = calendars_events_path
    end

    def prep_combined_index(calendar_scope)
      authorize(Event)
      prepare_lenses(community: {clearable: false})
      @rule_set = {}
      @can_create_event = writeable_calendars.any?
      setting = current_user.settings[:calendar_selection]
      @calendar_selection = InitialSelection.new(stored: setting, calendar_scope: calendar_scope).selection

      @new_event_path = new_calendars_event_path(origin_page: "combined")
      # Permalink doesn't need origin page
      @permalink = calendars_events_path
      # Feed path doesn't need calendar_id because the JS calendar view is responsible for inserting
      # whichever calendar ids the user selects, or the single ID in the case of single view.
      @feed_path = calendars_events_path(origin_page: "combined")
    end

    def writeable_calendars
      @writeable_calendars ||=
        CalendarPolicy::Scope.new(current_user, Calendar.in_community(current_community)).resolve_for_create
    end

    def render_json_event_list
      skip_policy_scope # This is checked in EventFinder and system calendars
      range = Time.zone.parse(params[:start])..Time.zone.parse(params[:end])
      calendars = Calendar.where(id: params[:calendar_ids]&.split(" "))
      events = EventFinder.new(range: range, calendars: calendars, user: current_user).events
      # The adapter option removes the root.
      render(json: events, adapter: :attributes, origin_page: params[:origin_page])
    end

    def render_form
      @calendar = Calendar.find(params[:calendar_id])
      @event = Event.new_with_defaults(
        calendar: @calendar,
        creator: current_user,
        starts_at: params[:start],
        ends_at: params[:end],
        origin_page: params[:origin_page]
      )
      authorize(@event)
      prep_form_vars
    end

    def prep_form_vars
      @calendar ||= @event.calendar
      @kinds = @calendar.kinds # May be nil
    end

    def render_choose_calendar_page
      @sample_event = Event.new(calendar: writeable_calendars.first, creator: current_user)
      authorize(@sample_event)
      @calendars = writeable_calendars
      @url_params = params.permit(:start, :end, :origin_page)
    end

    def handle_xhr_update
      if @event.update(event_params.merge(guidelines_ok: "1"))
        head(:ok)
      else
        render(partial: "update_error_messages", status: :unprocessable_entity)
      end
    end

    # We need to set the calendar separately from the other parameters because
    # the calendar is what determines the community, and that determines what attributes
    # are permitted to be set. So we don't allow calendar_id itself through permitted_attributes.
    def assign_calendar
      @event.calendar = Calendar.find(params[:calendars_event][:calendar_id])
    end

    # Pundit built-in helper doesn't work due to namespacing
    def event_params
      permitted = params.require(:calendars_event).permit(policy(@event).permitted_attributes)
      permitted[:privileged_changer] = true if policy(@event).privileged_change?
      permitted
    end

    def redirect_to_event_in_context(event)
      params = {date: event.starts_at&.to_s(:no_time)}
      params[:calendar_id] = event.calendar_id if event.origin_page != "combined"
      redirect_to(calendars_events_path(params))
    end
  end
end
