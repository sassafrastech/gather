# frozen_string_literal: true

require "rails_helper"

feature "sign in invitations", js: true do
  let(:actor) { create(:user, password: "ga4893d4bXq;", password_confirmation: "ga4893d4bXq;") }

  around { |ex| with_user_home_subdomain(actor) { ex.run } }

  scenario "validation errors and happy path" do
    full_sign_in_as(actor)
    visit(user_password_change_path(actor))

    fill_in("Current Password", with: "junk")
    fill_in("New Password", with: "foo")
    fill_in("Re-type New Password", with: "fo")
    click_on("Save")

    expect_validation_error("Is invalid")
    expect_validation_error(/was too weak/)
    expect_validation_error(/Didn't match/)

    fill_in("Current Password", with: DEFAULT_PASSWORD)
    fill_in("New Password", with: "48hafeirafar42")
    fill_in("Re-type New Password", with: "48hafeirafar42")
    click_on("Save")

    expect_success

    # Ensure the change worked.
    full_sign_out
    full_sign_in_as(actor, password: "48hafeirafar42")
    expect(page).to show_signed_in_user_name(actor.name)
  end
end
