% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/prediction_score.R
\name{prediction_score}
\alias{prediction_score}
\alias{prediction_score.default}
\alias{prediction_score.aphylo_estimates}
\alias{print.aphylo_prediction_score}
\title{Calculate prediction score (quality of prediction)}
\usage{
prediction_score(x, expected, alpha0 = NULL, alpha1 = NULL, W = NULL, ...)

\method{prediction_score}{default}(x, expected, alpha0 = NULL, alpha1 = NULL, W = NULL, ...)

\method{prediction_score}{aphylo_estimates}(
  x,
  expected = NULL,
  alpha0 = NULL,
  alpha1 = NULL,
  W = NULL,
  loo = TRUE,
  ...
)

\method{print}{aphylo_prediction_score}(x, ...)
}
\arguments{
\item{x}{An object of class \link{aphylo_estimates} or a numeric matrix.}

\item{expected}{Integer vector of length \eqn{n}. Expected values (either 0 or 1).}

\item{alpha0, alpha1}{Probability of observing a zero an a one, respectively.}

\item{W}{A square matrix. Must have as many rows as genes in \code{expected}.}

\item{...}{Further arguments passed to \link{predict.aphylo_estimates}}

\item{loo}{Logical scalar. When \code{loo = TRUE}, predictions are preformed
similar to what a leave-one-out cross-validation scheme would be done
(see \link{predict.aphylo_estimates}).}
}
\description{
Calculate prediction score (quality of prediction)
}
\details{
In the case of \code{prediction_score}, \code{...} are passed to
\code{predict.aphylo_estimates}.

In the case of the method for aphylo estimates, the function takes as
a reference using alpha equal to the proportion of observed tip annotations that
are equal to 1, this is:\preformatted{mean(x$dat$tip.annotation[x$dat$tip.annotation != 9L], na.rm = TRUE)
}
}
\examples{
# Example with prediction_score ---------------------------------------------
set.seed(11552)
ap  <- raphylo(
  50, P = 1,
  Pi   = 0,
  mu_d = c(.8,.2),
  mu_s = c(0.1,0.1),
  psi  = c(0,0)
  )
ans <- aphylo_mcmc(
  ap ~ mu_d + mu_s + Pi,
  control = list(nsteps=2e3, thin=20, burnin = 500),
  priors = bprior(c(9, 1, 1, 1, 5), c(1, 9, 9, 9, 5))
  )
                   
(pr <- prediction_score(ans, loo = TRUE))
plot(pr)
}
