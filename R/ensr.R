#' Elastic Net SearcheR
#'
#' Search a grid of values of alpha and lambda for minimum mean CV error
#'
#' @inheritParams glmnet::cv.glmnet
#' @inheritParams glmnet::glmnet
#' @param alphas a sequence of alpha values
#'
#' @export
ensr <- function(x, y, alphas = seq(0.00, 1.00, length = 10), nlambda = 100L, standardize = TRUE, nfolds = 10L, foldid, ...) {

  # build a single set of folds
  if (missing(foldid)) {
    foldid <- rep(seq(nfolds), length.out = nrow(x))
  }

  cl <- as.list(match.call())
  cl[[1]] <- quote(glmnet::cv.glmnet)
  cl$alphas <- NULL

  lmax <- lambda_max(y, x, alphas, standardize = standardize)
  lgrid <- lambda_alpha_grid(lmax, alphas, nlambda = nlambda)

  l_and_a <- split(lgrid$lgrid, lgrid$lgrid$a)

  models <- lapply(l_and_a,
                   function(la) {
                     cl$alpha <- la$a[1]
                     cl$lambda <- la$l
                     eval(as.call(cl))
                   })

  names(models) <- NULL

  class(models) <- "ensr"
  models
}

#' @export
print.ensr <- function(x, ...) {
  cat("A ensr object with", length(x), "cv.glmnet objects.\n")
  utils::str(x, max.level = 0L)
}

#' @export
summary.ensr <- function(object, ...) {
  out <-
    data.table::rbindlist(
      lapply(seq_along(object),
             function(idx) {
               data.table::data.table(l_index = idx,
                                      lambda = object[[idx]]$lambda,
                                      cvm    = object[[idx]]$cvm,
                                      nzero  = object[[idx]]$nzero,
                                      alpha  = as.list(object[[idx]]$glmnet.fit$call)$alpha)
             })
    )
  class(out) <- c("ensr_summary", class(out))
  out
}

#' @export
print.ensr_summary <- function(x, ...) {
  NextMethod("print")
}

#' @export
plot.ensr_summary <- function(x, type = c(1), ...) {

  if (1 %in% type) {
    sout <- data.table::copy(x)
    data.table::set(sout, j = "z", value = standardize(sout$cvm, stats = list(center = "min", scale = "sd")))
    imin <- which.min(sout$cvm)
    g1 <-
      ggplot2::ggplot(sout) +
      ggplot2::aes_string(x = "alpha", y = "lambda", z = "log10(z)", color = "log10(z)") +
      ggplot2::geom_point() +
      ggplot2::geom_contour() +
      ggplot2::scale_y_log10() +
      ggplot2::geom_point(data = sout[imin, ], cex = 2,  pch = 4, color = "red") +
      ggplot2::scale_color_gradient2(low = "#1b7837", high = "#762183") +
      ggplot2::xlab(expression(alpha)) +
      ggplot2::ylab(expression(lambda))
  }

  if (2 %in% type) {
    x2 <- data.table::copy(x) 
    x2 <- data.table::rbindlist(lapply(unique(x2$nzero), function(i) {
                                         x3 <- subset(x2, x2$nzero == i)
                                         subset(x3, x3$cvm == min(x3$cvm))
             }))

    g2 <- 
      ggplot2::ggplot(x2) +
      ggplot2::aes_string(x = "nzero", y = "cvm") +
      ggplot2::geom_line() +
      ggplot2::geom_point() 
  }

  if (all( c(1, 2) %in% type)) {
    gridExtra::grid.arrange(g1, g2, nrow = 1)
  } else if (1 %in% type) {
    g1
  } else if (2 %in% type) {
    g2
  } else {
    stop("Unknown plot type.")
  } 
}

#' @export
plot.ensr <- function(x, type = c(1), ...) {
  graphics::plot(summary(x), type = type, ...)
}

#' Predict Methods for ensr objects
#'
#' Using either the \code{lambda.min} or \code{lambda.1se}, find the preferable
#' model from the \code{ensr} object and return a prediction.
#'
#' The \code{glmnet::predict} argument \code{s} is ignored if specified and
#' attempted to be passed via \code{...}.  The value of \code{s} that is passed
#' to \code{glmnet::predict} is determined by the value of \code{lambda.min} or
#' \code{lambda.1se} found from a call to \code{\link{preferable}}.
#'
#' @inheritParams glmnet::predict.elnet
#' @param object a \code{ensr} object
#' @param ... other arguments passed along to \code{predict}
#' @name predict
#' @export
predict.ensr <- function(object, ...) {

  pm <- preferable(object)

  cl <- as.list(match.call())
  cl[[1]] <- quote(predict)

  cl$object <- pm

  cl$s <- pm$cv_row$lambda
  eval(as.call(cl))
}

#' @rdname predict
#' @export
coef.ensr <- function(object, ...) {
  cl <- as.list(match.call())
  cl[[1]] <- quote(predict)
  cl$type = "coefficients"
  eval(as.call(cl))
}

#' Preferable Elastic Net Model
#'
#' Find the preferable Elastic Net Model from an ensr object.  The preferable
#' model is defined as the model with the lowest mean cross validation error and
#' largest alpha value.
#'
#' @param object an ensr object
#' @param ... not currently used.
#' @export
preferable <- function(object, ...) {
  UseMethod("preferable")
}

#' @export
preferable.ensr <- function(object, ...) {

  sm <- summary(object)
  sm <- sm[sm[["cvm"]] == min(sm[["cvm"]]), ]

  if (nrow(sm) > 1L) {
    sm <- sm[sm[['alpha']] == max(sm[['alpha']])]
  }

  model_idx <- sm$l_index

  out <- object[[model_idx]]$glmnet.fit
  out$cv_row <- sm
  attr(out$cv_row, "call") <- match.call()
  class(out) <- c("ensr_pref", class(out))
  out
}

