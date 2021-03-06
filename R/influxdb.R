#' Create an influxdb_connection object
#'
#' @title influx_connection
#' @param host hostname
#' @param port numerical. port number
#' @param user username
#' @param pass password
#' @param group groupname
#' @param verbose logical. Provide additional details?
#' @param config_file The configuration file to be used if \code{groupname} is
#' specified.
#' @rdname influx_connection
#' @export
#' @author Dominik Leutnant (\email{leutnant@@fh-muenster.de})
#' @references \url{https://influxdb.com/}
influx_connection <-  function(host = NULL,
                               port = NULL,
                               scheme = "http",
                               user = "user",
                               pass = "pass",
                               group = NULL,
                               verbose = FALSE,
                               config_file = "~/.influxdb.cnf") {

  #' A group file looks like:
  #' [groupname]
  #' host=localhost
  #' port=8086
  #' user=username
  #' pass=password

  # if group name is given, get db credentials from config file
  if (!is.null(group)) {

    if (file.exists(config_file)) {

      # open file
      con <- file(config_file, open = "r")

      # read file
      lines <- readLines(con)

      # find line with groupname
      grp <- grep(paste0("[",group,"]"), x = lines, fixed = T)

      # catch the case if group name is not found
      if (identical(grp, integer(0))) stop("Group does not exist in config file.")

      # get db credentials
      host <- gsub("host=", "",
                   grep("host=",
                        lines[(grp + 1):(grp + 4)], fixed = T, value = T))
      port <- as.numeric(gsub("port=", "",
                              grep("port=",
                                   lines[(grp + 1):(grp + 4)], fixed = T,
                                   value = T)))
      user <- gsub("user=", "",
                   grep("user=",
                        lines[(grp + 1):(grp + 4)], fixed = T, value = T))
      pass <- gsub("pass=", "",
                   grep("pass=",
                        lines[(grp + 1):(grp + 4)], fixed = T, value = T))
      scheme <- gsub("scheme=", "", grep("scheme=", lines[(grp + 1):(grp + 4)], fixed = T, value = T))

      # close file connection
      close(con)

    } else{

      stop("Config file does not exist.")

    }

  }

  # create list of server connection details
  influxdb_srv <- list(host = host, port = port, scheme = scheme, user = user, pass = pass)

  # submit test ping
  response <- httr::GET(url = "", scheme = influxdb_srv$scheme,
                        hostname = influxdb_srv$host,
                        port = influxdb_srv$port,
                        path = "ping", httr::timeout(5))

  # print url
  if (verbose) print(response$url)

  # Check for communication errors
  if (response$status_code != 204) {
    if (length(response$content) > 0) warning(rawToChar(response$content))
    stop("Influx connection failed with HTTP status code ", response$status_code)
  }

  # print server response
  message(httr::http_status(response)$message)
  invisible(influxdb_srv)
}

#' Ping an influxdb server
#'
#' @title influx_ping
#' @param con An influx_connection object (s. \code{influx_connection}).
#'
#' @return A list of server information.
#' @rdname influx_ping
#' @export
#' @author Dominik Leutnant (\email{leutnant@@fh-muenster.de})
#' @seealso \code{\link[xts]{xts}}, \code{\link[influxdbr2]{influx_connection}}
#' @references \url{https://influxdb.com/docs/v0.9/concepts/api.html}
influx_ping <- function(con) {

  # submit ping
  response <- httr::GET(url = "",
                        scheme = con$scheme,
                        hostname = con$host,
                        port = con$port,
                        path = "ping")


  return(response$all_headers)

}
#' Query an influxdb server
#'
#' @title influx_query
#' @param con An influx_connection object (s. \code{influx_connection}).
#' @param db Sets the name of the database.
#' @param query The influxdb query to be sent.
#' @param timestamp_format Sets the timestamp format
#' ("default" (=UTC), "n", "u", "ms", "s", "m", "h").
#' @param return_xts logical. Sets the return type. If set to TRUE, xts objects
#' are returned, FALSE gives data.frames.
#' @param verbose logical. Provide additional details?
#'
#' @return A list of xts or data.frame objects.
#' @rdname influx_query
#' @export
#' @author Dominik Leutnant (\email{leutnant@@fh-muenster.de})
#' @seealso \code{\link[xts]{xts}}, \code{\link[influxdbr2]{influx_connection}}
#' @references \url{https://influxdb.com/docs/v0.9/concepts/api.html}
influx_query <- function(con,
                         db = NULL,
                         query = "SELECT * FROM measurement",
                         timestamp_format = "default",
                         return_xts = TRUE,
                         verbose = FALSE) {

  # development options
  debug <-  FALSE
  performance <- FALSE

  # create query based on function parameters
  q <- list(db = db, u = con$user, p = con$pass)

  # handle different timestamp formats
  if (timestamp_format != "default") {
    if (timestamp_format %in% c("n", "u", "ms", "s", "m", "h")) {
      q <- c(q, epoch = timestamp_format)
    } else {
      stop("Unknown timestamp format.")
    }
  }

  # add query
  q <- c(q, q = query)

  if (performance) print(paste(Sys.time(), "before query"))

  # submit query
  response <- httr::GET(url = "",
                        scheme = "http",
                        hostname = con$host,
                        port = con$port,
                        path = "query",
                        query = q)

  if (performance) print(paste(Sys.time(), "after query"))

  # print url
  if (verbose) print(response$url)


  # DEBUG OUTPUT
  if (debug) debug_influx_query_response_data <<- response

  # Check for communication errors
  if (response$status_code < 200 || response$status_code >= 300) {
    if (length(response$content) > 0)
      stop(rawToChar(response$content), call. = FALSE)
  }

  if (performance) print(paste(Sys.time(), "before json"))

  # parse response from json
  response_data <- jsonlite::fromJSON(rawToChar(response$content),
                                      simplifyVector = TRUE,
                                      simplifyDataFrame = FALSE,
                                      simplifyMatrix = FALSE)

  if (performance) print(paste(Sys.time(), "after json"))

  # Check for database or time series error
  if (exists(x = "error", where = response_data)) {
    stop(response_data$error, call. = FALSE)
  }

  # Check if query returned results
  if (exists(x = "results", where = response_data)) {

    # create list of results
    list_of_results <- sapply(response_data$results, function(resultsObj) {

      # check if query returned series object(s) with errors
      if (exists(x = "error", where = resultsObj)) {

        stop(resultsObj$error, call. = FALSE)

      } else {

        # check if query returned series object(s)
        if (exists(x = "series", where = resultsObj)) {

          if (performance) print(paste(Sys.time(), "before list_of_series"))

          # create list of series
          list_of_series <- lapply(resultsObj$series, function(seriesObj) {

            # check if response contains values
            if (exists(x = "values", where = seriesObj)) {

              ### TODO: What if response contains chunked time series?

              # extract values and columnnames
              values <- as.data.frame(do.call(rbind, seriesObj$values),
                                      stringsAsFactors = FALSE,
                                      row.names = NULL)

              # convert columns to most appropriate type
              # type.convert needs characters!
              values[] <- lapply(values, as.character)
              values[] <- lapply(values, type.convert, as.is = TRUE)

              # check if response contains columns
              if (exists(x = "columns", where = seriesObj)) {

                colnames(values) <- seriesObj$columns

                # check if response contains times
                # "Show Measurements", "Show Series", "Show Tag Keys"
                # and "Show Tag Values" queries do not provide "time"
                if ("time" %in% colnames(values)) {

                  # extract time vector to feed xts object
                  if (timestamp_format != "default") {

                    # when dealing with "millisecs", "nanosecs" or ... we need
                    # a divisor:
                    div <- switch(timestamp_format,
                                  "n" = 1e+9,
                                  "u" = 1e+6,
                                  "ms" = 1e+3,
                                  "s" = 1,
                                  "m" = 1/60,
                                  "h" = 1/(60*60))

                    time <- as.POSIXct(values[,'time']/div, origin = "1970-1-1")

                  } else {

                    time <- as.POSIXct(strptime(values[,'time'],
                                                format = "%Y-%m-%dT%H:%M:%OSZ"))

                  }

                  # select all but time vector to feed xts object
                  values <- values[, colnames(values) != 'time', drop = FALSE]

                  # should xts objects or data.frames be returned?
                  if (return_xts == TRUE) {

                    # create xts object for each returned column
                    # xts objects are based on matrix --> always one type only!
                    values <- lapply(values, function(x) xts::xts(x = x,
                                                                  order.by = time))

                    # assign colname and xtsAttributes
                    for (i in seq_len(length(values))) {
                      colnames(values[[i]]) <- seriesObj$columns[i + 1] # +1 to skip "time"
                      xts::xtsAttributes(values[[i]]) <- c(influx_query = query,
                                                           seriesObj$tags)
                    }

                    # assign measurement name
                    names(values) <- rep(seriesObj$name, length(values))

                    # return values as list of xts object(s)
                    return(values)

                  } else {

                    # return values as structure: data.frame with attributes
                    # with converted cols
                    values <- list( structure( cbind(time, values),
                                               influx_query = query,
                                               influx_tags = seriesObj$tags))

                    # assign measurement name
                    names(values) <- seriesObj$name

                    return(values)

                  }

                } else {

                  # return values as structure: data.frame with attributes
                  values <- list( structure( values,
                                             influx_query = query,
                                             influx_tags = seriesObj$tags))

                  # assign measurement name
                  names(values) <- seriesObj$name

                  return(values)

                }

              } else {

                warning("Influx query returned series with no columns.")

              }

            } else {

              warning("Influx query returned series with no values.")

            }

          })

          if (performance) print(paste(Sys.time(), "after list_of_series"))

          return(list_of_series)

        } else {

          #warning("Influx query returned no series.")

          return(NULL)

        }

      }

    })

    return(list_of_results)

  } else {

    warning("Influx query returned no results.")

    return(NULL)

  }

}



#' Query an influxdb server
#'
#' @title influx_query_xts
#' @param con An influx_connection object (s. \code{influx_connection}).
#' @param db Sets the name of the database.
#' @param query The influxdb query to be sent.
#' @param timestamp_format Sets the timestamp format
#' ("default" (=UTC), "n", "u", "ms", "s", "m", "h").
#' @param verbose logical. Provide additional details?
#'
#' @return A list of influx_series objects.
#'         Each influx_series object will have name, query, tags and values as members.
#'         name is usually the measurement name from which the data is fetched.
#'         values is a xts object representing the time series data
#'         tags is a list of tags associated with the series
#' @rdname influx_query_xts
#' @export
#' @author mvadu (\email{info@@adystech.com})
#' @seealso \code{\link[xts]{xts}}, \code{\link[influxdbr2]{influx_connection}}
#' @references \url{https://influxdb.com/docs/v0.9/concepts/api.html}
influx_query_xts <- function(con,
                             db = NULL,
                             query = "SELECT * FROM measurement",
                             timestamp_format = "default",
                             verbose = FALSE) {

  # development options
  debug <-  FALSE
  performance <- FALSE

  # create query based on function parameters
  q <- list(db = db, u = con$user, p = con$pass)

  # handle different timestamp formats
  if (timestamp_format != "default") {
    if (timestamp_format %in% c("n", "u", "ms", "s", "m", "h")) {
      q <- c(q, epoch = timestamp_format)
    } else {
      stop("Unknown timestamp format.")
    }
  }

  # add query
  q <- c(q, q = query)

  if (performance) print(paste(Sys.time(), "before query"))

  # submit query
  response <- httr::GET(url = "",
                        scheme = "http",
                        hostname = con$host,
                        port = con$port,
                        path = "query",
                        query = q)

  if (performance) print(paste(Sys.time(), "after query"))

  # print url
  if (verbose) print(response$url)


  # DEBUG OUTPUT
  if (debug) debug_influx_query_response_data <<- response

  # Check for communication errors
  if (response$status_code < 200 || response$status_code >= 300) {
    if (length(response$content) > 0)
      stop(rawToChar(response$content), call. = FALSE)
  }

  if (performance) print(paste(Sys.time(), "before json"))

  # parse response from json
  response_data <- jsonlite::fromJSON(rawToChar(response$content),
                                      simplifyVector = TRUE,
                                      simplifyDataFrame = FALSE,
                                      simplifyMatrix = FALSE)

  if (performance) print(paste(Sys.time(), "after json"))

  # Check for database or time series error
  if (exists(x = "error", where = response_data)) {
    stop(response_data$error, call. = FALSE)
  }

  # Check if query returned results
  if (exists(x = "results", where = response_data)) {

    # create list of results
    list_of_results <- sapply(response_data$results, function(resultsObj) {

      # check if query returned series object(s) with errors
      if (exists(x = "error", where = resultsObj)) {

        stop(resultsObj$error, call. = FALSE)

      } else {

        # check if query returned series object(s)
        if (exists(x = "series", where = resultsObj)) {

          if (performance) print(paste(Sys.time(), "before list_of_series"))

          # create list of series
          list_of_series <- lapply(resultsObj$series, function(seriesObj) {

            # check if response contains values
            if (exists(x = "values", where = seriesObj)) {

              ### TODO: What if response contains chunked time series?

              # extract values and columnnames
              values <- as.data.frame(do.call(rbind, seriesObj$values),
                                      stringsAsFactors = FALSE,
                                      row.names = NULL)

              # convert columns to most appropriate type
              # type.convert needs characters!
              values[] <- lapply(values, as.character)
              values[] <- lapply(values, type.convert, as.is = TRUE)

              # check if response contains columns
              if (exists(x = "columns", where = seriesObj)) {

                colnames(values) <- seriesObj$columns

                # check if response contains times
                # "Show Measurements", "Show Series", "Show Tag Keys"
                # and "Show Tag Values" queries do not provide "time"
                if ("time" %in% colnames(values)) {

                  # extract time vector to feed xts object
                  if (timestamp_format != "default") {

                    # when dealing with "millisecs", "nanosecs" or ... we need
                    # a divisor:
                    div <- switch(timestamp_format,
                                  "n" = 1e+9,
                                  "u" = 1e+6,
                                  "ms" = 1e+3,
                                  "s" = 1,
                                  "m" = 1/60,
                                  "h" = 1/(60*60))

                    time <- as.POSIXct(values[,'time']/div, origin = "1970-1-1")

                  } else {

                    time <- as.POSIXct(strptime(values[,'time'],
                                                format = "%Y-%m-%dT%H:%M:%OSZ"))
                  }

                  # select all but time vector to feed xts object
                  values <- values[, colnames(values) != 'time', drop = FALSE]

                  # should xts objects or data.frames be returned?
                  values <- as.xts(x = values, order.by = time)

                  xts::xtsAttributes(values) <- c(influx_query = query, seriesObj$tags)

                  return(structure( list(name = seriesObj$name,
                                         query = query,
                                         tags = seriesObj$tags,
                                         values = values),class = "influx_series"))

                } else {

                  return(structure( list(name = seriesObj$name,
                                         query = query,
                                         tags = seriesObj$tags,
                                         values = values),class = "influx_series"))
                }

              } else {

                warning("Influx query returned series with no columns.")

              }

            } else {

              warning("Influx query returned series with no values.")

            }

          })

          if (performance) print(paste(Sys.time(), "after list_of_series"))

          return(list_of_series)

        } else {

          #warning("Influx query returned no series.")

          return(NULL)

        }

      }

    })

    return(list_of_results)

  } else {

    warning("Influx query returned no results.")

    return(NULL)

  }

}

#' influx_select
#'
#' This function is a convenient wrapper for selecting data from a measurement
#' by calling \code{influx_query} with the corresponding query.
#'
#' @param con An influx_connection object (s. \code{influx_connection}).
#' @param db Sets the name of the database.
#' @param value Sets the name of values to be selected.
#' @param rp The name of the retention policy.
#' @param from Sets the name of the measurement.
#' @param where Apply filter on tag key values.
#' @param group_by The group_by clause in InfluxDB is used not only for
#' grouping by given values, but also for grouping by given time buckets.
#' @param limit Limits the number of the n oldest points to be returned.
#' @param slimit logical. Sets limiting procedure (slimit vs. limit).
#' @param offset Offsets the returned points by the value provided.
#' @param order_desc logical. Change sort order to descending.
#' @param return_xts logical. Sets the return type. If set to TRUE, xts objects
#' are returned, FALSE gives data.frames.
#'
#' @return A list of xts or data.frame objects.
#' @export
#' @references \url{https://influxdb.com/docs/v0.9/guides/querying_data.html}
influx_select <- function(con,
                          db,
                          value,
                          rp = NULL,
                          from,
                          where = NULL,
                          group_by = NULL,
                          limit = NULL,
                          slimit = FALSE,
                          offset = NULL,
                          order_desc = FALSE,
                          return_xts = TRUE) {

  if (!is.null(rp)) {
    options("useFancyQuotes" = FALSE)
    from <- paste(base::dQuote(rp), from, sep = ".")
  }

  query <- paste("SELECT", value, "FROM", from)

  query <- ifelse(is.null(where),
                  query,
                  paste(query, "WHERE", where))

  query <- ifelse(is.null(group_by),
                  query,
                  paste(query, "GROUP BY", group_by))

  query <- ifelse(!order_desc,
                  query,
                  paste(query, "ORDER BY time DESC"))

  query <- ifelse(is.null(limit),
                  query,
                  paste(query, ifelse(slimit, "SLIMIT", "LIMIT"), limit))

  query <- ifelse(is.null(offset),
                  query,
                  paste(query, "OFFSET", offset))

  result <- influx_query(con = con,
                         db = db,
                         query = query,
                         return_xts = return_xts,
                         verbose = FALSE)

  # concatenate list to get a more intuitive list
  result <- do.call(c,result)

  invisible(result)

}

#' Create database
#'
#' This function is a convenient wrapper for creating a database
#' by calling \code{influx_query} with the corresponding query.
#'
#' @title create_database
#' @param con An influx_connection object (s. \code{influx_connection}).
#' @param db Sets the target database to create.
#'
#' @return A list of server responses.
#' @rdname create_database
#' @export
#' @author Dominik Leutnant (\email{leutnant@@fh-muenster.de})
#' @seealso \code{\link[influxdbr2]{influx_connection}}
#' @references \url{https://influxdb.com/docs/v0.9/introduction/getting_started.html}
create_database <- function(con, db) {

  result <- influx_query(con = con,
                         db = db,
                         query = paste("CREATE DATABASE", db),
                         return_xts = FALSE)

  invisible(result)

}


#' Write an xts object to an influxdb server
#'
#'
#' @title influx_write
#' @param con An influx_connection object (s. \code{influx_connection}).
#' @param db Sets the target database for the write.
#' @param xts The xts object to write to an influxdb server.
#' @param tags The list of Tages (key value pairs) that should be written
#' @param measurement Sets the name of the measurement.
#' @param rp Sets the target retention policy for the write. If not present the
#' default retention policy is used.
#' @param precision Sets the precision of the supplied Unix time values
#' ("n", "u", "ms", "s", "m", "h"). If not present timestamps are assumed to be
#' in nanoseconds. Currently only "s" is supported.
#' @param consistency Set the number of nodes that must confirm the write.
#' If the requirement is not met the return value will be partial write
#' if some points in the batch fail, or write failure if all points in the batch
#' fail.
#' @param max_points Defines the maximum points per batch.
#' @param use_integers Should integers (instead of doubles) be written if present?
#' @param use_xts_attributes Should the xts attributes be used as tags along with tags list
#' @param treat_text_columns_as_tags Treat xts columns of pure text as tags, which are better
#' suited for influxDB
#' @return A list of server responses.
#' @rdname influx_write
#' @export
#' @author Dominik Leutnant (\email{leutnant@@fh-muenster.de}), mvadu (\email{info@@adystech.com})
#' @seealso \code{\link[xts]{xts}}, \code{\link[influxdbr2]{influx_connection}}
#' @references \url{https://influxdb.com/docs/v0.9/concepts/api.html}
influx_write <- function(con,
                         db,
                         xts,
                         tags = NULL,
                         measurement = NULL,
                         rp = NULL,
                         precision = "s",
                         consistency = NULL,
                         max_points = 5000,
                         use_integers = FALSE,
                         use_xts_attributes = TRUE,
                         treat_text_columns_as_tags = TRUE) {
  # development options
  performance <- FALSE

  # catch error no XTS object
  if (!xts::is.xts(xts))
    stop("Object is not an xts-object.")
  # catch error NULL colnames
  if (any(is.null(colnames(xts))))
    stop("colnames(xts) is NULL.")
  # catch error nrow
  if (nrow(xts) == 0)
    stop("nrow(xts) is 0.")

  tag_key_value = NULL
  if (!is.null(tags)) {
    if (!is.list(tags))
      stop("Tags is not an list-object.")
    if (any(is.null(names(tags))))
      stop("tag names is NULL.")

    tag_keys <- names(tags)
    tag_values <- tags

    # handle commas and spaces in values
    tag_values <-
      gsub(pattern = ",| ",
           replacement = "_",
           x = tag_values)

    # handle empty values in keys
    tag_values <- gsub(pattern = "numeric\\(0\\)|character\\(0\\)",
                       replacement = "NA",
                       x = tag_values)

    # merge tag keys and values
    tag_key_value <-
      paste(tag_keys, tag_values, sep = "=", collapse = ",")
  }

  if (use_xts_attributes == TRUE) {
    # extract tag keys and tag values
    tag_keys <- names(xts::xtsAttributes(xts))
    tag_values <- xts::xtsAttributes(xts)

    # handle commas and spaces in values
    tag_values <-
      gsub(pattern = ",| ",
           replacement = "_",
           x = tag_values)

    # handle empty values in keys
    tag_values <- gsub(pattern = "numeric\\(0\\)|character\\(0\\)",
                       replacement = "NA",
                       x = tag_values)

    # merge tag keys and values
    tag_key_values_attrib <-
      paste(tag_keys, tag_values, sep = "=", collapse = ",")
  }

  if ((!is.null(tags)) && (use_xts_attributes == TRUE)) {
    tag_key_value <-
      paste(tag_key_value, tag_key_values_attrib, sep = ",")
  } else if (use_xts_attributes == TRUE) {
    tag_key_value <- tag_key_values_attrib
  }

  # remove rows with NA's only
  xts <- xts[rowSums(is.na(xts)) != ncol(xts), ]

  # create query based on function parameters
  q <- list(db = db,
            u = con$user,
            p = con$pass)

  # add precision parameter
  if (!is.null(precision)) {
    if (precision %in% c("n", "u", "ms", "s", "m", "h")) {
      q <- c(q, precision = precision)

    } else {
      stop("bad parameter 'precision'. Must be one of 'n', 'u', 'ms', 's',
           'm', or 'h'")
    }

    }

  # add retention policy
  if (!is.null(rp))
    q <- c(q, rp = rp)

  # add consistency parameter
  if (!is.null(consistency)) {
    if (consistency %in% c("one", "quroum", "all", "any")) {
      q <- c(q, consistency = consistency)
    } else {
      stop("bad parameter 'consistency'. Must be one of 'one', 'quroum', 'all',
           or 'any'")
    }

    }

  # get no of points for performance analysis
  no_of_points <- nrow(xts)

  # split xts object into a list of xts objects to reduce batch size
  list_of_xts <- suppressWarnings(split(xts,
                                        rep(1:ceiling((nrow(xts) / max_points)
                                        ),
                                        each = max_points)))

  # reclass xts objects (became "zoo" in previous split command)
  list_of_xts <- lapply(list_of_xts, xts::as.xts)

  if (performance)
    start <- Sys.time()

  res <- lapply(list_of_xts, function(xts) {
    # create time vector
    pscale <- switch(
      precision,
      "n" = 1e+9,
      "u" = 1e+6,
      "ms" = 1e+3,
      "s" = 1,
      "m" = 1 / 60,
      "h" = 1 / (60 * 60)
    )
    time <-
      format(as.integer(as.numeric(zoo::index(xts)) * pscale), scientific = FALSE)

    #xts by design is a single type object. That means if the data.frame has a
    #single char column as.xts converts all numeric data to a char vector.
    #Inlfux DB needs different handling depending column type
    #(http://docs.influxdata.com/influxdb/v1.0/write_protocols/line_protocol_tutorial/).
    #So split the xts to individual columns,
    #and change the data type back to numeric if applicable.
    #Finally get a list of header=value pairs in influx format

    cols <- lapply(seq_len(ncol(xts)), function(x) {
      column = (xts[, x])
      #convert back to numeric types if the colums has numeric data
      tryCatch({
        storage.mode(column) <- "numeric"
      }
      , warning = function(war) {
        storage.mode(column) <- "character"
      }, error = function(err) {
        stop(err)
      })

      if (is.numeric(column)) {
        if ((use_integers == TRUE) & all(column == floor(column))) {
          column[, ] <-
            sapply(seq_len(ncol(column)), function(x) {
              ifelse(is.na(column[, x]), NA, paste(column[, x], "i", sep = ""))
            })
        }
        values <-
          paste(colnames(column), zoo::coredata(column), sep = "=")
        return(structure(list(
          Values = values, tags = NULL
        )))
      } else {
        if (treat_text_columns_as_tags) {
          values <- paste(colnames(column), zoo::coredata(column), sep = "=")
          return(structure(list(
            Values = NULL, tags = values
          )))
        } else{
          # add quotes if matrix contains no numerics i.e. -> characters
          op <- options("useFancyQuotes")
          options("useFancyQuotes" = FALSE)
          column[, ] <-
            sapply(seq_len(ncol(column)), function(x)
              base::dQuote(column[, x]))
          options(op)
          # trim leading and trailing whitespaces
          column <- gsub("^\\s+|\\s+$", "", column)
          values <-
            paste(colnames(column), zoo::coredata(column), sep = "=")
          return(structure(list(
            Values = values, tags = NULL
          )))
        }
      }

    })

    tag_col_count = length(which(sapply(cols, function(x)
      sum(is.null(
        x[[1]]
      ))) > 0))
    value_col_count = length(which(sapply(cols, function(x)
      sum(!is.null(
        x[[1]]
      ))) > 0))

    if (value_col_count == 0)
      stop("InfluxDB needs atealst one value for each point")

    #merge the individual columns to a matrix
    value_matrix = matrix(unlist(lapply(cols, function(x)
      paste(x[[1]]))), ncol = value_col_count, byrow = FALSE)

    # set R's NA values to a replace with magic (random) string which can be removed easily
    # -> influxdb doesn't handle NA values
    magic <-
      paste(sample(c(0:9, letters, LETTERS), 15, replace = TRUE), collapse =
              "")
    value_matrix[grepl("=NA", value_matrix)] <- magic

    # If values have only one row, 'apply' will result in a dim error.
    # This occurs if the previous 'sapply' result a character vector.
    # Thus, check if a conversion is required:
    if (is.null(dim(value_matrix))) {
      dim(value_matrix) <- length(value_matrix)
    }

    # paste and collapse rows
    values <- apply(value_matrix, 1, paste, collapse = ",")


    if (tag_col_count > 0)
    {
      tag_matrix <-
        matrix(unlist(lapply(cols, function(x)
          paste(x[[2]]))), ncol = tag_col_count, byrow = FALSE)
      if (!is.null(tag_key_value))
        tag_matrix <- cbind(tag_matrix, tag_key_value)
      tag_key_value <- apply(tag_matrix, 1, paste, collapse = ",")
    }

    # no tags assigned
    if (is.null(tag_key_value) |
        identical(character(0), tag_key_value)) {
      influxdb_line_protocol <- paste(measurement,
                                      values,
                                      time)
    } else {
      influxdb_line_protocol <- paste(measurement,
                                      paste(",", tag_key_value, sep = ""),
                                      " ",
                                      values,
                                      " ",
                                      time,
                                      sep = "")
    }

    # remove dummy strings
    influxdb_line_protocol <-
      paste(influxdb_line_protocol[!grepl(magic, influxdb_line_protocol)], collapse = "\n")

    # submit post
    response <- httr::POST(
      url = "",
      httr::timeout(60),
      scheme = "http",
      hostname = con$host,
      port = con$port,
      path = "write",
      query = q,
      body = influxdb_line_protocol
    )


    # Check for communication errors
    if (response$status_code < 200 || response$status_code >= 300) {
      if (length(response$content) > 0)
        stop(rawToChar(response$content), call. = FALSE)
    }

    # assign server response to list "res"
    rawToChar(response$content)

  })

  if (performance)
    message(paste(
      "Wrote",
      no_of_points,
      "points in",
      Sys.time() - start,
      "seconds."
    ))

  invisible(res)

}
