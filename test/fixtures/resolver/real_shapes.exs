defmodule MyAppWeb.AccountControllerTest do
  use MyAppWeb.ConnCase

  alias MyApp.Accounts
  import MyApp.Factory, only: [insert: 1]

  describe "index" do
    import MyAppWeb.RouteHelpers, only: [route_path: 1]

    test "lists accounts", %{conn: conn} do
      import MyApp.Assertions, only: [assert_account: 1]

      build_conn()
      accounts = for role <- [:admin, :member], do: Accounts.list(role)
      assert_account(accounts)
      route_path(conn)
      insert(:account)
    end
  end
end

defmodule MyApp.DataCaseTest do
  use MyApp.DataCase

  test "macro DSL" do
    MyApp.Schema.field(:name)
  end
end
