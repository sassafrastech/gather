# frozen_string_literal: true

module Meals
  # For finalizing meals.
  class FinalizeController < ApplicationController
    helper_method :signups
    before_action -> { nav_context(:meals, :meals) }
    decorates_assigned :meal

    def new
      @meal = Meal.find(params[:meal_id])
      authorize @meal, :finalize?
      @dupes = []
      build_meal_cost
      prepare_and_render_form
    end

    def create
      @meal = Meal.find(params[:meal_id])
      authorize @meal, :finalize?

      # We assign finalized here so that the meal/signup validations don't complain about no spots left.
      @meal.assign_attributes(finalize_params.merge(status: "finalized"))

      # Need to build the meal cost object so it can hold validation errors.
      build_meal_cost

      if @meal.valid?
        params[:confirmed] == "0" ? handle_unconfirmed : handle_valid
      else
        handle_invalid
      end
    end

    def signups
      @signups ||= @meal.signups.map(&:decorate)
    end

    private

    def handle_unconfirmed
      flash.now[:notice] = t("meals.finalizing.cancelled")
      prepare_and_render_form
    end

    def handle_valid
      # Run the save and signup in a transaction in case
      # the finalize operation fails or we need to confirm.
      Meal.transaction do
        @finalizer = Meals::Finalizer.new(@meal)
        if params[:confirmed] == "1"
          complete_process
        else
          show_confirmation_page
        end
      end
    end

    def complete_process
      @finalizer.finalize!
      @meal.save!
      flash[:success] = t("meals.finalizing.success")
      redirect_to(meals_path(finalizable: 1))
    end

    def show_confirmation_page
      @calculator = @finalizer.calculator
      @cost = @meal.cost
      flash.now[:alert] = t("meals.finalizing.review_and_confirm_html").html_safe
      prepare_and_render_form(:confirm)
    end

    def handle_invalid
      set_validation_error_notice(@meal)
      prepare_and_render_form
    end

    def prepare_and_render_form(template = :new)
      # We rerendering form, need to set status back to closed or the policy won't let us edit stuff.
      @meal.status = "closed" if @meal.finalized?
      render(template)
    end

    def build_meal_cost
      @meal.build_cost if @meal.cost.nil?
    end

    def finalize_params
      params.require(:meal).permit(
        signups_attributes: [:id, :household_id, lines_attributes: %i[id quantity item_id]],
        cost_attributes: %i[ingredient_cost pantry_cost payment_method]
      )
    end
  end
end
