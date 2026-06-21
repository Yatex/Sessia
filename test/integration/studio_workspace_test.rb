require "test_helper"

class StudioWorkspaceTest < ActionDispatch::IntegrationTest
  test "new user can sign up as a studio" do
    post sign_up_url, params: {
      user: {
        name: "Wellness Studio",
        email: "studio-signup@example.com",
        password: "password123",
        password_confirmation: "password123",
        time_zone: "America/Montevideo",
        account_type: "studio"
      }
    }

    assert_redirected_to dashboard_url
    assert User.find_by!(email: "studio-signup@example.com").studio?
  end

  test "studio can create a professor team member" do
    studio = User.create!(name: "Studio Owner", email: "studio-owner@example.com", password: "password123", account_type: "studio")
    post sign_in_url, params: { email: studio.email, password: "password123" }

    assert_difference -> { studio.studio_teachers.count }, 1 do
      post team_members_url, params: {
        user: {
          name: "Team Professor",
          email: "team-professor@example.com",
          password: "password123",
          password_confirmation: "password123",
          time_zone: "America/Montevideo",
          locale: "en"
        }
      }
    end

    teacher = User.find_by!(email: "team-professor@example.com")
    assert teacher.professional?
    assert_equal studio, teacher.studio_owner
    assert_redirected_to team_members_url
  end

  test "studio sees team clients and sessions while professor only sees their own records" do
    studio = User.create!(name: "Studio", email: "studio@example.com", password: "password123", account_type: "studio")
    teacher = studio.studio_teachers.create!(name: "Studio Teacher", email: "teacher@example.com", password: "password123")
    client = teacher.clients.create!(name: "Visible Student", phone: "+598 99 123 222")
    teacher.sessions.create!(
      client: client,
      title: "Team Session",
      start_time: Time.current.beginning_of_week(:monday) + 10.hours,
      end_time: Time.current.beginning_of_week(:monday) + 11.hours
    )

    outsider = User.create!(name: "Outside Teacher", email: "outside@example.com", password: "password123")
    outsider_client = outsider.clients.create!(name: "Hidden Student", phone: "+598 99 123 223")
    outsider.sessions.create!(
      client: outsider_client,
      title: "Hidden Session",
      start_time: Time.current.beginning_of_week(:monday) + 12.hours,
      end_time: Time.current.beginning_of_week(:monday) + 13.hours
    )

    post sign_in_url, params: { email: studio.email, password: "password123" }
    get clients_url
    assert_response :success
    assert_match "Visible Student", response.body
    assert_match "Studio Teacher", response.body
    assert_no_match "Hidden Student", response.body

    get sessions_url
    assert_response :success
    assert_match "Team Session", response.body
    assert_no_match "Hidden Session", response.body

    delete sign_out_url
    post sign_in_url, params: { email: teacher.email, password: "password123" }
    get clients_url
    assert_response :success
    assert_match "Visible Student", response.body
    assert_no_match "Hidden Student", response.body
    assert_no_match "Outside Teacher", response.body
  end

  test "studio can create a client assigned to a professor" do
    studio = User.create!(name: "Studio", email: "studio-create-client@example.com", password: "password123", account_type: "studio")
    teacher = studio.studio_teachers.create!(name: "Assigned Teacher", email: "assigned@example.com", password: "password123")
    post sign_in_url, params: { email: studio.email, password: "password123" }

    assert_difference -> { teacher.clients.count }, 1 do
      post clients_url, params: {
        client: {
          user_id: teacher.id,
          name: "Assigned Client",
          phone: "+598 99 123 225",
          status: "active"
        }
      }
    end

    assert_redirected_to client_url(Client.find_by!(name: "Assigned Client"))
  end

  test "studio can choose the professor when creating a session" do
    studio = User.create!(name: "Studio", email: "studio-create-session@example.com", password: "password123", account_type: "studio")
    first_teacher = studio.studio_teachers.create!(name: "First Teacher", email: "first-session-teacher@example.com", password: "password123")
    selected_teacher = studio.studio_teachers.create!(name: "Selected Teacher", email: "selected-session-teacher@example.com", password: "password123")
    hidden_client = first_teacher.clients.create!(name: "Hidden Client", phone: "+598 99 123 230")
    selected_client = selected_teacher.clients.create!(name: "Selected Client", phone: "+598 99 123 231")
    start_time = Time.current.beginning_of_week(:monday) + 10.hours

    post sign_in_url, params: { email: studio.email, password: "password123" }

    get new_session_url(user_id: selected_teacher.id)
    assert_response :success
    assert_select "select[name='session[user_id]']"
    assert_match "Selected Teacher", response.body
    assert_match "Selected Client", response.body
    assert_no_match "Hidden Client", response.body

    assert_difference -> { selected_teacher.sessions.count }, 1 do
      post sessions_url, params: {
        session: {
          user_id: selected_teacher.id,
          client_id: selected_client.id,
          title: "Chosen Professor Session",
          start_time: start_time,
          end_time: start_time + 1.hour,
          confirmation_status: "confirmed",
          payment_status: "pending",
          price: "0",
          currency: "ARS"
        }
      }
    end

    session_record = Session.find_by!(title: "Chosen Professor Session")
    assert_equal selected_teacher, session_record.user
    assert_equal selected_client, session_record.client
    assert_not_equal hidden_client, session_record.client
  end

  test "studio all-professors agenda renders professors as columns for selected day" do
    studio = User.create!(name: "Studio", email: "studio-agenda@example.com", password: "password123", account_type: "studio")
    teacher = studio.studio_teachers.create!(name: "Agenda Teacher", email: "agenda-teacher@example.com", password: "password123")
    client = teacher.clients.create!(name: "Agenda Client", phone: "+598 99 123 226")
    start_time = Time.current.beginning_of_week(:monday) + 9.hours
    teacher.sessions.create!(
      client: client,
      title: "Agenda Session",
      start_time: start_time,
      end_time: start_time + 1.hour,
      confirmation_status: "confirmed",
      payment_status: "paid"
    )

    post sign_in_url, params: { email: studio.email, password: "password123" }
    get dashboard_url(view: "week", date: start_time.to_date.iso8601)

    assert_response :success
    assert_select ".studio-day-strip"
    assert_select ".resource-grid-professor", text: /Agenda Teacher/
    assert_match "Agenda Client", response.body
    assert_select "main .section-heading h2", text: "Payments", count: 0
  end

  test "studio all-professors agenda shows empty state when no professor has sessions that day" do
    studio = User.create!(name: "Studio", email: "studio-empty-agenda@example.com", password: "password123", account_type: "studio")
    studio.studio_teachers.create!(name: "Empty Agenda Teacher", email: "empty-agenda-teacher@example.com", password: "password123")

    post sign_in_url, params: { email: studio.email, password: "password123" }
    get dashboard_url(view: "week", date: Date.current.iso8601)

    assert_response :success
    assert_select ".studio-day-strip"
    assert_select ".studio-empty-day"
    assert_select ".resource-grid", count: 0
    assert_select "main .section-heading h2", text: "Payments", count: 0
  end
end
