class ApplicationController < ActionController::Base
  include Pundit

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  before_action :authenticate_user!

  # Verify that controller actions are authorized.
  after_action :verify_authorized,  except: :index, unless: :devise_controller?
  after_action :verify_policy_scoped, only: :index

  helper_method :home_path

  def set_validation_error_notice
    flash.now[:error] = "Please correct the errors below."
  end

  def redirect_to_home
    redirect_to home_path
  end

  def home_path
    current_user.try(:inactive?) ? inactive_path : root_path
  end

  def after_sign_in_path_for(resource)
    home_path
  end
end
