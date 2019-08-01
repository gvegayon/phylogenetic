#' Fancy pattern for replacement:
#' (
#'   [a-zA-Z0-9]+\\[.+\\]: Something with brackets
#'   c\\(.+\\): Something with a vector
#'   [a-zA-Z0-9.]+: Just something
#' )
#' \\s*(?=$|[,]|\\)): Followed by a comma, parenthesis, line end, or )
#'   
#' PATTERN <- c("([a-zA-Z0-9]+\\[.+\\]|c\\(.+\\)|[a-zA-Z0-9.]+)\\s*(?=[,]|\\)|$)")
update_fun_in_body <- function(f, var, replacement) {
  
  pattern <- c("([a-zA-Z0-9]+\\[.+\\]|c\\([a-zA-Z0-9\\.,\\s_\\\"]+\\)|[a-zA-Z0-9.-]+)\\s*(?=$|[,]|\\))")
  
  # Getting the data
  f_txt <- deparse(f, width.cutoff = 500L)
  
  # Creating the match and replacement
  replacement <- paste(var, "=", replacement)
  var         <- paste0(var, "\\s*[=]\\s*", pattern)
  
  eval(parse(text = gsub(var, replacement, f_txt, perl = TRUE)))
  
}

#' This function takes a pattern, looks for the matching line, and comments
#' it out 
comment_line_in_body <- function(f, pattern, ...) {
  
  f_txt <- deparse(f, width.cutoff = 500L)
  test <- which(grepl(pattern, f_txt, ...))
  if (length(test))
    f_txt[test] <- "# "
  eval(parse(text = f_txt))
  
}


#' Formulas in `aphylo`
#' 
#' @param ... Either 0, 1 or both. Depending on the parameter, the index of the
#' model parameter that will be set as fixed.
#' @param fm A formula. Model of the type `<aphylo-object> ~ <parameters>` (see 
#' examples).
#' @param priors (optional) A function. Prior for the model.
#' @param env Environment (not to be called by the user).
#' @param params Numeric vector with model parameters.
#' @return A list with the following elements:
#' * `fun` A function. The log-likelihood function.
#' * `fixed` Logical vector. 
#' 
#' @examples
#' set.seed(12)
#' x <- raphylo(10)
#' 
#' # Baseline model
#' aphylo_formula(x ~ mu_d)
#' 
#' # Mislabeling probabilities
#' aphylo_formula(x ~ mu_d + psi)
#' 
#' # Different probabilities for speciation and duplication node
#' # (only works if you have both types)
#' aphylo_formula(x ~ mu_d + mu_s + psi)
#' 
#' # Mislabeling probabilities and etas(fixed)
#' aphylo_formula(x ~ mu_d + psi + eta(0, 1))
#' 
#' # Mislabeling probabilities and Pi 
#' aphylo_formula(x ~ mu_d + psi + Pi)
#' 
#' @name aphylo-model
#' @aliases aphylo-formula
NULL

APHYLO_PARAM_NAMES <- c(
  "psi0", "psi1", "mu_d0", "mu_d1", "mu_s0", "mu_s1",
  "eta0", "eta1", "Pi"
  )
APHYLO_PARAM_DEFAULT <- structure(
  .Data = c(.1, .1, .9, .9, .1, .1, .9, .9, .1),
  names = APHYLO_PARAM_NAMES
)

#' @rdname aphylo-model
#' @export
aphylo_call <- function(params, priors) {
  
  ans <- list2env(
    list(
      fun = function(p, dat, priors, verb_ans = FALSE) {
        
        # Call
        ans <- LogLike(
          tree = dat,
          psi  = c(0, 0),
          mu_d = p[c("mu_d0", "mu_d1")],
          mu_s = p[c("mu_d0", "mu_d1")],
          eta  = c(.5, .5),
          Pi   = -1, # Negative default means compute it using the approx
          verb_ans = verb_ans
        )
        
        # Correcting for eta
        ans$ll <- ans$ll + 0.69314718055994528623*sum(Nann(dat))*sum(Nannotated(dat))
        
        # Adding priors
        ans$ll <- ans$ll + sum(log(priors(p)))
        
        if (is.infinite(ans$ll)) {
          ans$ll <- .Machine$double.xmax*sign(ans$ll)*1e-10
        }
        
        # If verbose (not by default)
        if (verb_ans) {
          ans
        } else {
          ans$ll
        }
    },
    fixed = structure(
      .Data = rep(FALSE, length(params)),
      names = names(params)
      ),
    params = params
  ))
  
  if (!missing(priors))
    formals(ans$fun)$priors <- priors
  
  ans
}

validate_dots_in_term <- function(..., expected) {
  
  # Who called me?
  parent_call <- sys.calls()
  parent_call <- parent_call[[length(parent_call) - 1]][[1]]
  parent_call <- as.character(parent_call)
  
  dots <- list(...)
  
  # Capturing dots
  dots <- unlist(list(...))
  if (length(dots) && !all(dots %in% c(0, 1)))
    stop(
      "Arguments passed to `",
      parent_call,
      "`, if any, should be any of {",
      paste0(expected, collapse=", "),
      "}.",
      call. = FALSE
      )
  
  dots
  
}

#' @rdname aphylo-model
eta <- function(..., env) {
  
  # Updating parameters
  env$fun <- update_fun_in_body(env$fun, "eta", "c(p[\"eta0\"], p[\"eta1\"])")
  
  # Removing the eta correction
  env$fun <- comment_line_in_body(env$fun, "sum(Nann(dat))", fixed = TRUE)
  
  # Adding eta to the objective function
  env$fixed[c("eta0", "eta1")] <- FALSE
  
  
  # Updating
  dots <- validate_dots_in_term(..., expected = c(0,1))
  for (f in dots) 
    env$fixed[paste0("eta", f)] <- TRUE
  
  invisible()
}

#' @rdname aphylo-model
psi <- function(..., env) {
  
  # if (on_covr(env)) {
  #   body(env$fun)[[2]][[2]][[3]][[3]]$psi  <- bquote(c(p["psi0"], p["psi1"]))
  # } else {
  #   body(env$fun)[[2]][[3]]$psi  <- bquote(c(p["psi0"], p["psi1"]))
  # }

  # Updating the likelihood function  
  env$fun <- update_fun_in_body(env$fun, "psi", "c(p[\"psi0\"], p[\"psi1\"])")
  
  # Adding eta to the objective function
  env$fixed[c("psi0", "psi1")] <- FALSE

  # Updating
  dots <- validate_dots_in_term(..., expected = c(0,1))
  for (f in dots) 
    env$fixed[paste0("psi", f)] <- TRUE
  
  invisible()
}

#' @rdname aphylo-model
Pi <- function(..., env) {
  
  # Adding eta to the objective function
  # if (on_covr(env)) {
  #   body(env$fun)[[2]][[2]][[3]][[3]]$Pi <- bquote(p["Pi"])
  # } else {
  #   body(env$fun)[[2]][[3]]$Pi <- bquote(p["Pi"])
  # }
  # Updating the likelihood function  
  env$fun <- update_fun_in_body(env$fun, "Pi", "p[\"Pi\"]")
  
  env$fixed["Pi"] <- FALSE
  
  # Updating (if fixed, then we set whatever value should be included)
  dots <- validate_dots_in_term(..., expected = 0)
  for (f in dots)
    env$fixed[paste0("Pi")] <- TRUE
  
  invisible()
}

#' @rdname aphylo-model
mu_d <- function(..., env) {

  # Updating
  dots <- validate_dots_in_term(..., expected = c(0,1))
  for (f in dots)
    env$fixed[paste0("mu_s", f)] <- TRUE
  
  invisible()
}

#' @rdname aphylo-model
mu_s <- function(..., env) {
  
  # Updating
  dots <- validate_dots_in_term(..., expected = c(0,1))
  for (f in dots)
    env$fixed[paste0("mu_s", f)] <- TRUE
  
  # Updating parameters
  # if (on_covr(env)) {
  #   body(env$fun)[[2]][[2]][[3]][[3]]$mu_s <- bquote(c(p["mu_s0"], p["mu_s1"]))
  # } else {
  #   body(env$fun)[[2]][[3]]$mu_s <- bquote(c(p["mu_s0"], p["mu_s1"]))
  # }
  env$fun <- update_fun_in_body(env$fun, "mu_s", "c(p[\"mu_s0\"], p[\"mu_s1\"])")
  
  invisible()
}


#' Basic validations:
#' 1. Are all terms valid terms?
#' 2. Is there any repeated term?
#' @noRd
validate_aphylo_formula <- function(fm) {
  
  # Extracting terms
  fm1  <- stats::terms(fm, keep.order = TRUE)
  vars <- attr(fm1, "term.labels")
  term_names <- gsub("\\(.+", "", vars)
  
  # Analyzing the terms, are all 
  TNAMES <- unique(gsub("[0-9]", "", APHYLO_PARAM_NAMES))
  test. <- which(!(term_names %in% TNAMES))
  
  if (length(test.)) {
    stop("The following terms in the formula are not supported by `aphylo`: '",
         paste0(vars[test.], collapse = "', '"), "'. ", 
         "Only `", paste(TNAMES, collapse="()`, `"), "()` are allowed.",
         call. = FALSE)
  }
  
  # Is there any repeated term?
  test. <- table(term_names)
  test. <- names(test.)[which(test. > 1)]
  if (length(test.)) {
    stop("Some terms are repeated more than once: '",
         paste0(vars[term_names %in% test.], collapse = "', '"), "'.",
         call. = FALSE
         )
  }
  
  # Is mu present?
  if (!("mu_d" %in% term_names))
    fm <- stats::update.formula(fm, ~. + mu_d)
  
  fm
  
  
}

#' This function validates the parameters specified
#' @noRd
validate_parameters <- function(fm, params) {
  
  # Extracting formula terms
  vars <- attr(stats::terms(fm), "term.labels")
  vars <- gsub("\\(.+", "", vars)
  
  
  # Getting the default
  vars <- paste0("^(",paste0(vars, collapse="|"), ")")
  vars <- APHYLO_PARAM_NAMES[grepl(vars, x = APHYLO_PARAM_NAMES)]
  
  # In the case of missing parameters, then return the default according to
  # what the formula is.
  if (missing(params)) {
    
    # message("No parameters were specified. Default will be used instead.")
    return(APHYLO_PARAM_DEFAULT[vars])
    
  } else {
    
    # Retrieving name of the parameters
    pnames <- switch(
      class(params),
      matrix = colnames(params),
      names(params)
      )
    
    # Checking length
    if (!length(pnames)) {
      
      # If unnamed, are we giving enough information?
      npars <- switch (class(params),
        matrix = ncol(params),
        length(params)
      )
      if (npars != length(vars))
        stop("The initial parameters have different length than specified in ",
             "the model.", call.=FALSE)
      
      # Matching names by position
      warning("Initial parameres matched by position.", call. = FALSE)
      
      if (is.matrix(params)) 
        return(structure(.Data = params, dimnames = list(NULL, vars)))
      else
        return(structure(.Data = params, names = vars))
      
    }
    
    # More than needed
    test. <- which(!(pnames %in% vars))
    if (length(test.)) {
      stop(
        "The initial parametes must match those specified in the model. ",
        "The following parameters have been overspecified: '",
        paste(pnames[test.], collapse = "', '"), "'. These should ",
        "match the following set of parameters: '",
        paste(vars, collapse = "', '"), "'.", 
        call. = FALSE
        )
    }
    
    # Less than required
    test. <- which(!(vars %in% pnames))
    if (length(test.)) {
      stop(
        "The initial parametes must match those specified in the model. ",
        "The following parameters are missing: '",
        paste(vars[test.], collapse = "', '"), "'. These should ",
        "match the following set of parameters: '",
        paste(vars, collapse = "', '"), "'.", 
        call. = FALSE
      )
    }
    
    # Sorting accordingly
    if (is.matrix(params))
      params[,vars,drop=FALSE]
    else
      params[vars]
    
  }
  
}

#' @rdname aphylo-model
#' @export
aphylo_formula <- function(fm, params, priors, env = parent.frame()) {
  
  # Validating formula
  fm  <- validate_aphylo_formula(fm)
  val <- attr(stats::terms(fm), "variables")
  
  # Validating initial parameters
  params <- validate_parameters(fm, params)
  
  # Creating new aphylo call object
  model_call <- aphylo_call(params, priors)
  
  # Is the LHS an aphylo object?
  if (!exists(as.character(val[[2]]), envir = env))
    stop("The object -", as.character(val[[2]]), "- can't be found.", call. = FALSE)
  
  LHS <- eval(val[[2]], envir = env)
  if (!is.aphylo(LHS) && !is.multiAphylo(LHS))
    stop(
      "The LHS of the equation should be either a list or a single ",
      "aphylo object.", call. = FALSE)
  
  # Mofiying the likelihood function and the parameters for the mcmc
  # saveRDS(val, "~/Desktop/val.rds")
  # saveRDS(model_call, "~/Desktop/model_call.rds")
  for (i in 3:length(val))
    if (!is.call(val[[i]])) {
      eval(
        call(as.character(val[[i]]), env = bquote(model_call))
      )
    } else {
      val[[i]]$env <- bquote(model_call)
      eval(val[[i]])
    }
  
  # Returning the model call as a list
  c(
    list(
      model  = fm,
      dat    = eval(val[[2]], env)
      ),
    as.list(model_call)
  )
    
}
