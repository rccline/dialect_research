# Loard packages
# r-script-database-setup.R

library(DBI)
library(RPostgres)
library(readr)
library(dplyr)
library(stringr)
library(tidyr)
library(ggplot2)
library(DT)
library(shiny)
library(knitr)
library(rmarkdown)

# EBSCO Repository Database Setup and Import
# This script:
# 1. Creates a PostgreSQL database for tracking repository holdings
# 2. Imports EBSCO CSV data
# 3. Provides functions for managing repositories and holdings

# Load required libraries
library(DBI)
library(RPostgres)
library(readr)
library(dplyr)
library(stringr)
library(tidyr)

# -----------------------
# Database Configuration
# -----------------------
# Replace these with your PostgreSQL credentials
db_config <- list(
  dbname = "ebsco_repositories",
  host = "localhost",
  port = 5432,
  user = "postgres",      # Replace with your username
  password = "5232"   # Replace with your password
)

# -----------------------
# Database Connection
# -----------------------
connect_to_db <- function(config = db_config) {
  tryCatch({
    # Connect to PostgreSQL
    con <- dbConnect(
      RPostgres::Postgres(),
      dbname = config$dbname,
      host = config$host,
      port = config$port,
      user = config$user,
      password = config$password
    )
    message("Successfully connected to PostgreSQL database")
    return(con)
  }, error = function(e) {
    message("Failed to connect to the database: ", e$message)
    return(NULL)
  })
}

# -----------------------
# Database Setup
# -----------------------
setup_database <- function(con, sql_file = "repository_schema.sql") {
  tryCatch({
    # Create database schema by reading SQL file
    sql_schema <- readLines(sql_file)
    sql_schema <- paste(sql_schema, collapse = "\n")
    
    # Execute SQL commands
    dbExecute(con, sql_schema)
    
    message("Database schema created successfully")
  }, error = function(e) {
    message("Error creating database schema: ", e$message)
  })
}

# -----------------------
# EBSCO CSV Import Functions
# -----------------------
import_ebsco_csv <- function(con, csv_file) {
  tryCatch({
    # Read the CSV file
    message("Reading CSV file: ", csv_file)
    ebsco_data <- readr::read_csv(csv_file, show_col_types = FALSE)
    
    # Import process started
    message("Starting import process for ", nrow(ebsco_data), " records")
    
    # Process each record
    for (i in 1:nrow(ebsco_data)) {
      row <- ebsco_data[i,]
      
      # Insert into References table
      dbWithTransaction(con, {
        # Insert basic record
        query <- "
          INSERT INTO \"References\" (
            \"EBSCO_AN\", \"Title\", \"Abstract\", \"PublicationDate\", \"Contributors\",
            \"DocumentType\", \"PublicationType\", \"CoverDate\", \"Subjects\",
            \"ISBN\", \"ISSN\", \"Language\", \"Publisher\", \"DOI\", \"SourceDB\", \"PermanentLink\"
          ) 
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
          ON CONFLICT DO NOTHING
          RETURNING \"ReferenceID\"
        "
        
        # Execute query with parameters
        result <- dbGetQuery(con, query, params = list(
          as.numeric(row$an),
          row$title,
          row$abstract,
          as.numeric(row$publicationDate),
          row$contributors,
          row$docTypes,
          row$pubTypes,
          row$coverDate,
          row$subjects,
          row$isbns,
          row$issns,
          row$language,
          row$publisher,
          row$doi,
          row$longDBName,
          row$plink
        ))
        
        # Get the reference ID
        ref_id <- NULL
        if (nrow(result) > 0) {
          ref_id <- result$ReferenceID[1]
        } else {
          # If insertion failed (already exists), query for the ID
          id_query <- "SELECT \"ReferenceID\" FROM \"References\" WHERE \"EBSCO_AN\" = $1"
          id_result <- dbGetQuery(con, id_query, params = list(as.numeric(row$an)))
          if (nrow(id_result) > 0) {
            ref_id <- id_result$ReferenceID[1]
          }
        }
        
        if (!is.null(ref_id)) {
          # Process ISBNs if present
          if (!is.na(row$isbns) && row$isbns != "") {
            isbns <- strsplit(row$isbns, "\\s*;\\s*")[[1]]
            for (isbn in isbns) {
              if (isbn != "") {
                isbn_query <- "
                  INSERT INTO \"Identifiers\" (\"ReferenceID\", \"IdentifierType\", \"IdentifierValue\")
                  VALUES ($1, $2, $3)
                  ON CONFLICT DO NOTHING
                "
                dbExecute(con, isbn_query, params = list(ref_id, "ISBN", isbn))
              }
            }
          }
          
          # Process ISSNs if present
          if (!is.na(row$issns) && row$issns != "") {
            issns <- strsplit(row$issns, "\\s*;\\s*")[[1]]
            for (issn in issns) {
              if (issn != "") {
                issn_query <- "
                  INSERT INTO \"Identifiers\" (\"ReferenceID\", \"IdentifierType\", \"IdentifierValue\")
                  VALUES ($1, $2, $3)
                  ON CONFLICT DO NOTHING
                "
                dbExecute(con, issn_query, params = list(ref_id, "ISSN", issn))
              }
            }
          }
          
          # Process Subjects if present
          if (!is.na(row$subjects) && row$subjects != "") {
            subjects <- strsplit(row$subjects, "\\s*;\\s*")[[1]]
            for (subject in subjects) {
              if (subject != "") {
                # Insert subject if it doesn't exist
                subject_query <- "
                  INSERT INTO \"Subjects\" (\"SubjectName\")
                  VALUES ($1)
                  ON CONFLICT DO NOTHING
                  RETURNING \"SubjectID\"
                "
                subject_result <- dbGetQuery(con, subject_query, params = list(subject))
                
                # Get subject ID
                subject_id <- NULL
                if (nrow(subject_result) > 0) {
                  subject_id <- subject_result$SubjectID[1]
                } else {
                  # If subject already exists, query for its ID
                  subject_id_query <- "SELECT \"SubjectID\" FROM \"Subjects\" WHERE \"SubjectName\" = $1"
                  subject_id_result <- dbGetQuery(con, subject_id_query, params = list(subject))
                  if (nrow(subject_id_result) > 0) {
                    subject_id <- subject_id_result$SubjectID[1]
                  }
                }
                
                # Link reference to subject
                if (!is.null(subject_id)) {
                  ref_subject_query <- "
                    INSERT INTO \"ReferenceSubjects\" (\"ReferenceID\", \"SubjectID\")
                    VALUES ($1, $2)
                    ON CONFLICT DO NOTHING
                  "
                  dbExecute(con, ref_subject_query, params = list(ref_id, subject_id))
                }
              }
            }
          }
          
          # Process Contributors if present
          if (!is.na(row$contributors) && row$contributors != "") {
            contributors <- strsplit(row$contributors, "\\s*;\\s*")[[1]]
            for (contributor in contributors) {
              if (contributor != "") {
                # Insert contributor if it doesn't exist
                contributor_query <- "
                  INSERT INTO \"Contributors\" (\"ContributorName\")
                  VALUES ($1)
                  ON CONFLICT DO NOTHING
                  RETURNING \"ContributorID\"
                "
                contributor_result <- dbGetQuery(con, contributor_query, params = list(contributor))
                
                # Get contributor ID
                contributor_id <- NULL
                if (nrow(contributor_result) > 0) {
                  contributor_id <- contributor_result$ContributorID[1]
                } else {
                  # If contributor already exists, query for its ID
                  contributor_id_query <- "SELECT \"ContributorID\" FROM \"Contributors\" WHERE \"ContributorName\" = $1"
                  contributor_id_result <- dbGetQuery(con, contributor_id_query, params = list(contributor))
                  if (nrow(contributor_id_result) > 0) {
                    contributor_id <- contributor_id_result$ContributorID[1]
                  }
                }
                
                # Link reference to contributor
                if (!is.null(contributor_id)) {
                  # Default role to Author
                  role <- "Author"
                  
                  ref_contributor_query <- "
                    INSERT INTO \"ReferenceContributors\" (\"ReferenceID\", \"ContributorID\", \"ContributorRole\")
                    VALUES ($1, $2, $3)
                    ON CONFLICT DO NOTHING
                  "
                  dbExecute(con, ref_contributor_query, params = list(ref_id, contributor_id, role))
                }
              }
            }
          }
        }
      })
      
      # Progress update
      if (i %% 10 == 0 || i == nrow(ebsco_data)) {
        message("Processed ", i, " of ", nrow(ebsco_data), " records")
      }
    }
    
    message("EBSCO data import completed successfully")
    return(TRUE)
  }, error = function(e) {
    message("Error importing EBSCO data: ", e$message)
    return(FALSE)
  })
}

# -----------------------
# Repository Management Functions
# -----------------------
add_repository <- function(con, repo_data) {
  tryCatch({
    query <- "
      INSERT INTO \"Repositories\" (
        \"RepositoryName\", \"RepositoryType\", \"Institution\", 
        \"City\", \"State\", \"Country\", \"WebsiteURL\", 
        \"ContactEmail\", \"ContactPhone\", \"Notes\"
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING \"RepositoryID\"
    "
    
    result <- dbGetQuery(con, query, params = list(
      repo_data$name,
      repo_data$type,
      repo_data$institution,
      repo_data$city,
      repo_data$state,
      repo_data$country,
      repo_data$website,
      repo_data$email,
      repo_data$phone,
      repo_data$notes
    ))
    
    if (nrow(result) > 0) {
      message("Repository added with ID: ", result$RepositoryID[1])
      return(result$RepositoryID[1])
    } else {
      message("Failed to add repository")
      return(NULL)
    }
  }, error = function(e) {
    message("Error adding repository: ", e$message)
    return(NULL)
  })
}

list_repositories <- function(con) {
  tryCatch({
    query <- "
      SELECT 
        \"RepositoryID\", \"RepositoryName\", \"Institution\", 
        \"City\", \"State\", \"Country\"
      FROM \"Repositories\"
      ORDER BY \"RepositoryName\"
    "
    
    result <- dbGetQuery(con, query)
    return(result)
  }, error = function(e) {
    message("Error listing repositories: ", e$message)
    return(NULL)
  })
}

# -----------------------
# Holdings Management Functions
# -----------------------
add_holding <- function(con, holding_data) {
  tryCatch({
    query <- "
      INSERT INTO \"Holdings\" (
        \"ReferenceID\", \"RepositoryID\", \"Format\", 
        \"CallNumber\", \"LocationNote\", \"AccessRestriction\",
        \"VerificationDate\", \"Notes\"
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING \"HoldingID\"
    "
    
    result <- dbGetQuery(con, query, params = list(
      holding_data$reference_id,
      holding_data$repository_id,
      holding_data$format,
      holding_data$call_number,
      holding_data$location_note,
      holding_data$access_restriction,
      holding_data$verification_date,
      holding_data$notes
    ))
    
    if (nrow(result) > 0) {
      message("Holding added with ID: ", result$HoldingID[1])
      return(result$HoldingID[1])
    } else {
      message("Failed to add holding")
      return(NULL)
    }
  }, error = function(e) {
    message("Error adding holding: ", e$message)
    return(NULL)
  })
}

get_reference_holdings <- function(con, reference_id) {
  tryCatch({
    query <- "
      SELECT 
        h.\"HoldingID\", r.\"RepositoryName\", h.\"Format\", 
        h.\"CallNumber\", h.\"LocationNote\", h.\"AccessRestriction\",
        h.\"VerificationDate\", h.\"Notes\"
      FROM \"Holdings\" h
      JOIN \"Repositories\" r ON h.\"RepositoryID\" = r.\"RepositoryID\"
      WHERE h.\"ReferenceID\" = $1
      ORDER BY r.\"RepositoryName\"
    "
    
    result <- dbGetQuery(con, query, params = list(reference_id))
    return(result)
  }, error = function(e) {
    message("Error retrieving holdings: ", e$message)
    return(NULL)
  })
}

# -----------------------
# Search Functions
# -----------------------
search_references <- function(con, search_params) {
  tryCatch({
    # Build query based on search parameters
    base_query <- "
      SELECT DISTINCT
        r.\"ReferenceID\", r.\"Title\", r.\"Contributors\", 
        r.\"DocumentType\", r.\"Publisher\", r.\"CoverDate\",
        r.\"ISBN\", r.\"ISSN\", r.\"DOI\"
      FROM \"References\" r
    "
    
    # Start with empty WHERE clause and params list
    where_clauses <- c()
    params <- list()
    param_index <- 1
    
    # Add conditions based on search parameters
    if (!is.null(search_params$title) && search_params$title != "") {
      where_clauses <- c(where_clauses, paste0("r.\"Title\" ILIKE $", param_index))
      params[[param_index]] <- paste0("%", search_params$title, "%")
      param_index <- param_index + 1
    }
    
    if (!is.null(search_params$author) && search_params$author != "") {
      where_clauses <- c(where_clauses, paste0("r.\"Contributors\" ILIKE $", param_index))
      params[[param_index]] <- paste0("%", search_params$author, "%")
      param_index <- param_index + 1
    }
    
    if (!is.null(search_params$identifier) && search_params$identifier != "") {
      where_clauses <- c(where_clauses, paste0("(r.\"ISBN\" ILIKE $", param_index, 
                                               " OR r.\"ISSN\" ILIKE $", param_index,
                                               " OR r.\"DOI\" ILIKE $", param_index, ")"))
      params[[param_index]] <- paste0("%", search_params$identifier, "%")
      param_index <- param_index + 1
    }
    
    if (!is.null(search_params$subject) && search_params$subject != "") {
      # Join with Subjects tables
      base_query <- paste0(base_query, "
        LEFT JOIN \"ReferenceSubjects\" rs ON r.\"ReferenceID\" = rs.\"ReferenceID\"
        LEFT JOIN \"Subjects\" s ON rs.\"SubjectID\" = s.\"SubjectID\"
      ")
      where_clauses <- c(where_clauses, paste0("s.\"SubjectName\" ILIKE $", param_index))
      params[[param_index]] <- paste0("%", search_params$subject, "%")
      param_index <- param_index + 1
    }
    
    # Combine WHERE clauses if any exist
    full_query <- base_query
    if (length(where_clauses) > 0) {
      full_query <- paste0(full_query, " WHERE ", paste(where_clauses, collapse = " AND "))
    }
    
    # Add ORDER BY
    full_query <- paste0(full_query, " ORDER BY r.\"Title\"")
    
    # Execute query
    result <- dbGetQuery(con, full_query, params = params)
    return(result)
  }, error = function(e) {
    message("Error searching references: ", e$message)
    return(NULL)
  })
}

# -----------------------
# Example Usage
# -----------------------
# Uncomment to run

# # Connect to database
# con <- connect_to_db()
# 
# # Create schema (first time setup)
# setup_database(con, "repository_schema.sql")
# 
# # Import EBSCO data
# import_ebsco_csv(con, "Ebscodialects.csv")
# 
# # Add a repository
# repo_data <- list(
#   name = "University Library",
#   type = "Academic",
#   institution = "State University",
#   city = "Columbus",
#   state = "OH",
#   country = "USA",
#   website = "https://library.university.edu",
#   email = "library@university.edu",
#   phone = "555-123-4567",
#   notes = "Main campus library"
# )
# repo_id <- add_repository(con, repo_data)
# 
# # Search for references
# search_params <- list(
#   title = "language",
#   author = "",
#   identifier = "",
#   subject = "German"
# )
# results <- search_references(con, search_params)
# print(results)
# 
# # Close connection


# dbDisconnect(con)