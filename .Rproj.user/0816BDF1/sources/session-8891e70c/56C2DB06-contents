library(DBI)
library(RPostgres)
library(dplyr)

# Connect to your database
con <- dbConnect(
  RPostgres::Postgres(),
  dbname = "ebsco_repositories",
  host = "localhost",
  port = 5432,
  user = "postgres",
  password = "5232"  # Use your actual password
)

# List all tables in the database
dbListTables(con)

# Example 1: View all references
references <- dbGetQuery(con, 'SELECT * FROM "References"')
View(references)  # Opens in RStudio data viewer

# Example 2: View books only
books <- dbGetQuery(con, 'SELECT * FROM "References" WHERE "DocumentType" = \'Book\'')
View(books)

# Example 3: View journals
journals <- dbGetQuery(con, 'SELECT * FROM "References" WHERE "DocumentType" = \'Journal Article\'')
View(journals)

# Example 4: Get repositories
repositories <- dbGetQuery(con, 'SELECT * FROM "Repositories"')
View(repositories)

# Example 5: Get holdings with repository names (which libraries have which references)
holdings_query <- '
  SELECT r."Title", rep."RepositoryName", h."Format", h."CallNumber", h."LocationNote"
  FROM "Holdings" h
  JOIN "References" r ON h."ReferenceID" = r."ReferenceID"
  JOIN "Repositories" rep ON h."RepositoryID" = rep."RepositoryID"
  ORDER BY r."Title"
'
holdings <- dbGetQuery(con, holdings_query)
View(holdings)

# Example 6: Find all locations for a specific book (by title search)
find_book_locations <- function(title_search) {
  query <- '
    SELECT r."Title", rep."RepositoryName", h."Format", h."CallNumber", h."LocationNote"
    FROM "Holdings" h
    JOIN "References" r ON h."ReferenceID" = r."ReferenceID"
    JOIN "Repositories" rep ON h."RepositoryID" = rep."RepositoryID"
    WHERE r."Title" ILIKE $1
    ORDER BY rep."RepositoryName"
  '
  results <- dbGetQuery(con, query, params = list(paste0("%", title_search, "%")))
  return(results)
}

# Example usage: Find all repositories that have books about "dialect"
dialect_books <- find_book_locations("dialect")
View(dialect_books)

# Remember to close the connection when you're done
dbDisconnect(con)


##%######################################################%##
#                                                          #
####     Which repositories have the most holdings?     ####
#                                                          #
##%######################################################%##

repository_counts <- dbGetQuery(con, '
  SELECT rep."RepositoryName", COUNT(*) as total_holdings
  FROM "Holdings" h
  JOIN "Repositories" rep ON h."RepositoryID" = rep."RepositoryID"
  GROUP BY rep."RepositoryName"
  ORDER BY total_holdings DESC
')
View(repository_counts)

# Which references are held by the most repositories?
popular_references <- dbGetQuery(con, '
  SELECT r."Title", COUNT(DISTINCT h."RepositoryID") as repository_count
  FROM "Holdings" h
  JOIN "References" r ON h."ReferenceID" = r."ReferenceID"
  GROUP BY r."Title"
  ORDER BY repository_count DESC
  LIMIT 20
')
View(popular_references)