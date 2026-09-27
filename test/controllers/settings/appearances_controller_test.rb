require "test_helper"

class Settings::AppearancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
  end

  test "offers the OLED theme" do
    get settings_appearance_url

    assert_response :success
    assert_select "input[type=radio][name='user[theme]'][value=oled]"
  end

  test "saving OLED renders the page dark with true-black surfaces" do
    patch user_url(@user), params: { user: { theme: "oled", redirect_to: "appearance" } }

    assert_redirected_to settings_appearance_path
    assert_equal "oled", @user.reload.theme

    get settings_appearance_url

    assert_select "html[data-theme=dark][data-oled][data-theme-user-preference-value=oled]"
    assert_select "input[type=radio][name='user[theme]'][value=oled][checked]"
  end

  test "dark theme does not opt into OLED surfaces" do
    @user.update!(theme: "dark")

    get settings_appearance_url

    assert_select "html[data-theme=dark]"
    assert_select "html[data-oled]", count: 0
  end
end
