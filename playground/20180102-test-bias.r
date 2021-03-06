rm(list = ls())

library(aphylo)

n <- 200
N <- 500

set.seed(111222)
PAR <- lapply(1:N, function(i) rbeta(5, 2, 20))
SIZ <- ceiling(runif(N, 4, 400))
DAT <- lapply(seq_along(PAR), function(p) raphylo(SIZ[p], psi=PAR[[p]][1:2], mu=PAR[[p]][3:4], Pi=PAR[[p]][5]))

plot_LogLike(DAT[[1]], psi = c(.1, .1), mu = c(.1, .1), Pi=.1)

est <- function(d) {
  tryCatch({
    aphylo_mcmc(params = rep(.05,5), dat = d , control=list(nbatch=5e3, burnin=1e3, thin=10),
                priors = function(u) dbeta(u, 2, 20))
  }, error = function(e) e)
}

# x <- profvis::profvis(x <- raphylo(10000))
# htmlwidgets::saveWidget(x, "~/profile.html")
# browseURL("~/profile.html")

cl <- parallel::makeForkCluster(4)
ANS <- parallel::parLapply(cl, DAT, est)
# ANS <- lapply(DAT, est)
parallel::stopCluster(cl)

PARest <- lapply(ANS, "[[", "par")

OK <- which(grepl("aphy", sapply(sapply(ANS, class), "[[", 1)))

PARest <- do.call(rbind, PARest[OK])
PARh0  <- do.call(rbind, lapply(1:length(OK), function(i) rbeta(5, 2, 20)))

bias   <- PARest - do.call(rbind, PAR[OK])
biash0 <- PARh0 - do.call(rbind, PAR[OK])

oldpar <- par(no.readonly = TRUE)
par(mfrow = c(1, 2))
boxplot(bias, main = "Non random", ylim = c(-.5, .5))
boxplot(biash0, main = "Random", ylim = c(-.5, .5))
par(oldpar)
summary(bias)
summary(biash0)

hist(sapply(ANS[OK], "[[", "counts"))
prop.table(table(abs(bias) < abs(biash0)))
