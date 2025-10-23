alias TokenApp.{Repo}
alias TokenApp.Tokens.Token

count = Repo.aggregate(Token, :count, :id)

if count == 0 do
  now = DateTime.utc_now()

  entries =
    for _ <- 1..100 do
      %{
        uuid: Ecto.UUID.generate(),
        inserted_at: now,
        updated_at: now
      }
    end

  Repo.insert_all(Token, entries)
  IO.puts("Seeded 100 tokens.")
else
  IO.puts("Tokens already seeded (#{count} present).")
end
