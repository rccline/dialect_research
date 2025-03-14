library(DBI)
library(RPostgres)

# Connect to database
con <- tryCatch({
  dbConnect(
    RPostgres::Postgres(),
    dbname = "ebsco_repositories",
    host = "localhost",
    port = 5432,
    user = "postgres",      # Update with your actual username
    password = "5232"   # Update with your actual password
  )
}, error = function(e) {
  message("Connection error: ", e$message)
  return(NULL)
})

if (!is.null(con)) {
  # Try simple query
  result <- dbGetQuery(con, 'SELECT COUNT(*) AS count FROM "References"')
  print("Database connection successful!")
  print(paste("Reference count:", result$count))
  
  # Try another query to get some actual records
  sample_refs <- dbGetQuery(con, 'SELECT "ReferenceID", "Title" FROM "References" LIMIT 5')
  print("Sample references:")
  print(sample_refs)
  
  # Disconnect
  dbDisconnect(con)
} else {
  print("Could not connect to database")
}