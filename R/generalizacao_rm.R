random_machines_meu <- function(formula, train, validation, boots_size = 25, cost = 10,
                                degree = 2, seed.bootstrap = NULL, automatic_tuning = FALSE,
                                gamma_rbf = 1, gamma_lap = 1, poly_scale = 1, offset = 0, gamma_cau = 1, d_t = 2,
                                kernels = c("rbfdot", "polydot", "laplacedot", "vanilladot", "cauchydot", "tdot"),
                                prob_model = T) {
  cauchydot <- function(sigma = 1) {
    norma <- function(x, y) {
      return(Rfast::Norm(matrix(x - y)))
    }

    rval <- function(x, y = NULL) {
      if (!is(x, "vector")) {
        stop("x must be a vector")
      }
      if (!is(y, "vector") && !is.null(y)) {
        stop("y must a vector")
      }
      if (is(x, "vector") && is.null(y)) {
        return(1)
      }
      if (is(x, "vector") && is(y, "vector")) {
        if (!length(x) == length(y)) {
          stop("number of dimension must be the same on both data points")
        }
        return(1 / (1 + (norma(x, y) / sigma)))
      }
    }
    return(new("kernel", .Data = rval, kpar = list(sigma = sigma)))
  }


  tdot <- function(d = 2) {
    norma <- function(x, y, d) {
      return(sqrt(Rfast::Norm(matrix(x - y)))^d)
    }

    rval <- function(x, y = NULL) {
      if (!is(x, "vector")) {
        stop("x must be a vector")
      }
      if (!is(y, "vector") && !is.null(y)) {
        stop("y must a vector")
      }
      if (is(x, "vector") && is.null(y)) {
        return(1)
      }
      if (is(x, "vector") && is(y, "vector")) {
        if (!length(x) == length(y)) {
          stop("number of dimension must be the same on both data points")
        }
        return(1 / (1 + norma(x, y, d)))
      }
    }
    return(new("kernel", .Data = rval, kpar = list(d = d)))
  }

  if (prob_model == T) {
    test <- validation
    class_name <- as.character(formula[[2]])
    prob_weights <- list()
    kernel_type <- kernels
    if (automatic_tuning) {
      early_model <- purrr::map(kernel_type, ~ kernlab::ksvm(formula,
        prob.model = T,
        data = train, type = "C-svc", kernel = if (.x == "vanilladot") {
          "polydot"
        } else if (.x == "cauchydot") {
          cauchydot()
        } else if (.x == "tdot") {
          tdot()
        } else {
          .x
        }, C = cost, kpar = if (.x == "laplacedot" || .x == "rbfdot") {
          "automatic"
        } else if (.x == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.x == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.x == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    } else {
      early_model <- purrr::map(kernel_type, ~ kernlab::ksvm(formula,
        prob.model = T,
        data = train, type = "C-svc", kernel = if (.x ==
          "vanilladot") {
          "polydot"
        } else if (.x == "cauchydot") {
          cauchydot()
        } else if (.x == "tdot") {
          tdot()
        } else {
          .x
        }, C = cost, kpar = if (.x == "laplacedot") {
          list(sigma = gamma_lap)
        } else if (.x == "rbfdot") {
          list(sigma = gamma_rbf)
        } else if (.x == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.x == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.x == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    }
    predict <- purrr::map(early_model, ~ kernlab::predict(.x,
      newdata = test, type = "probabilities"
    )[, 2])
    brier <- purrr::map(predict, ~ measures::Brier(probabilities = .x, truth = unlist(test[, class_name]), negative = 0, positive = 1)) %>% unlist()
    log_brier <- log((1 - brier) / brier)
    log_brier[is.infinite(log_brier)] <- 1 # Sometimes the brier can be equal to 0, so this line certify to not produce any NA
    prob_weights <- log_brier / sum(log_brier)
    prob_weights <- ifelse(prob_weights < 0, 0, prob_weights) # To not heve negative values of probabilities

    models <- rep(list(0), boots_size)
    boots_sample <- list(rep(boots_size))
    out_of_bag <- list(rep(boots_size))
    boots_index_row <- list(nrow(train)) %>% rep(boots_size)
    at_least_one <- NULL
    if (is.null(seed.bootstrap)) {
      while (is.null(at_least_one)) {
        boots_index_row_new <- purrr::map(
          boots_index_row,
          ~ sample(1:.x, .x, replace = TRUE)
        )
        boots_sample <- purrr::map(boots_index_row_new, ~ train[.x, ])
        out_of_bag <- purrr::map(boots_index_row_new, ~ train[-unique(.x), ])
        ## a classe y==1 precisa ter mais de 1 observacao (duas ou mais)
        for (p in 1:length(boots_sample)) {
          while (table(boots_sample[[p]][class_name])[2] < 2) {
            boots_index_row_new_new <- purrr::map(
              boots_index_row,
              ~ sample(1:.x, .x, replace = TRUE)
            )
            boots_sample_new <- purrr::map(boots_index_row_new_new, ~ train[.x, ])
            out_of_bag_new <- purrr::map(boots_index_row_new_new, ~ train[-unique(.x), ])

            boots_sample[[p]] <- boots_sample_new[[1]]
            out_of_bag[[p]] <- out_of_bag_new[[1]]
          }
        }
        ##
        if (any(unlist(lapply(boots_sample, function(x) {
          table(x[[class_name]]) == 0
        })))) {
          at_least_one <- NULL
        } else {
          at_least_one <- 1
        }
      }
    } else {
      set.seed(seed.bootstrap)
      while (is.null(at_least_one)) {
        boots_index_row_new <- purrr::map(
          boots_index_row,
          ~ sample(1:.x, .x, replace = TRUE)
        )
        boots_sample <- purrr::map(boots_index_row_new, ~ train[.x, ])
        out_of_bag <- purrr::map(boots_index_row_new, ~ train[-unique(.x), ])
        ## a classe y==1 precisa ter mais de 1 observacao (duas ou mais)
        for (p in 1:length(boots_sample)) {
          while (table(boots_sample[[p]][class_name])[2] < 2) {
            boots_index_row_new_new <- purrr::map(
              boots_index_row,
              ~ sample(1:.x, .x, replace = TRUE)
            )
            boots_sample_new <- purrr::map(boots_index_row_new_new, ~ train[.x, ])
            out_of_bag_new <- purrr::map(boots_index_row_new_new, ~ train[-unique(.x), ])

            boots_sample[[p]] <- boots_sample_new[[1]]
            out_of_bag[[p]] <- out_of_bag_new[[1]]
          }
        }
        ##
        if (any(unlist(lapply(boots_sample, function(x) {
          table(x[[class_name]]) == 0
        })))) {
          at_least_one <- NULL
        } else {
          at_least_one <- 1
        }
      }
    }
    random_kernel <- sample(kernel_type, boots_size, replace = TRUE, prob = prob_weights)
    if (automatic_tuning) {
      models <- purrr::map2(boots_sample, random_kernel, ~ kernlab::ksvm(formula,
        prob.model = T,
        data = .x, type = "C-svc", kernel = if (.y == "vanilladot") {
          "polydot"
        } else if (.y == "cauchydot") {
          cauchydot()
        } else if (.y == "tdot") {
          tdot()
        } else {
          .y
        }, C = cost, kpar = if (.y == "laplacedot" || .y ==
          "rbfdot") {
          "automatic"
        } else if (.y == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.y == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.y == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    } else {
      models <- purrr::map2(boots_sample, random_kernel, ~ kernlab::ksvm(formula,
        prob.model = T,
        data = .x, type = "C-svc", kernel = if (.y == "vanilladot") {
          "polydot"
        } else if (.y == "cauchydot") {
          cauchydot()
        } else if (.y == "tdot") {
          tdot()
        } else {
          .y
        }, C = cost, kpar = if (.y == "laplacedot") {
          list(sigma = gamma_lap)
        } else if (.y == "rbfdot") {
          list(sigma = gamma_rbf)
        } else if (.y == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.y == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.y == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    }
    predict <- purrr::map(models, ~ kernlab::predict(.x, newdata = test, type = "probabilities")[, 2])
    predict_oobg <- purrr::map2(models, out_of_bag, ~ kernlab::predict(.x,
      newdata = .y, type = "probabilities"
    )[, 2])
    kernel_weight_raw <- purrr::map2(predict_oobg, out_of_bag, ~ Brier(.x, unlist(.y[, class_name]), negative = 0, positive = 1)) %>% unlist()
    kernel_weight <- 1 / kernel_weight_raw^2

    kern_names_final <- kernel_type %>%
      as_tibble() %>%
      mutate(value = case_when(
        value == "rbfdot" ~ "RBF_Kern",
        value == "polydot" ~ "Pol_Kern",
        value == "laplacedot" ~ "LAP_Kern",
        value == "vanilladot" ~ "Lin_Kern",
        value == "cauchydot" ~ "CAU_Kern",
        value == "tdot" ~ "T_Kern"
      )) %>%
      pull(value)

    if (length(kern_names_final) == 2) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 3) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 4) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3],
          prob_weights[4]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 5) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3],
          prob_weights[4],
          prob_weights[5]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 6) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3],
          prob_weights[4],
          prob_weights[5],
          prob_weights[6]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else {
      print("N??mero de Kernels n??o compat??vel")
    }


    attr(model_result, "class") <- "rm_model"
    return(model_result)
  } else {
    test <- validation
    class_name <- as.character(formula[[2]])
    prob_weights <- list()
    kernel_type <- kernels
    if (automatic_tuning) {
      early_model <- purrr::map(kernel_type, ~ kernlab::ksvm(formula,
        data = train, type = "C-svc", kernel = if (.x ==
          "vanilladot") {
          "polydot"
        } else if (.x == "cauchydot") {
          cauchydot()
        } else if (.x == "tdot") {
          tdot()
        } else {
          .x
        }, C = cost, kpar = if (.x == "laplacedot" || .x ==
          "rbfdot") {
          "automatic"
        } else if (.x == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.x == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.x == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    } else {
      early_model <- purrr::map(kernel_type, ~ kernlab::ksvm(formula,
        data = train, type = "C-svc", kernel = if (.x ==
          "vanilladot") {
          "polydot"
        } else if (.x == "cauchydot") {
          cauchydot()
        } else if (.x == "tdot") {
          tdot()
        } else {
          .x
        }, C = cost, kpar = if (.x == "laplacedot") {
          list(sigma = gamma_lap)
        } else if (.x == "rbfdot") {
          list(sigma = gamma_rbf)
        } else if (.x == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.x == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.x == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    }
    predict <- purrr::map(early_model, ~ kernlab::predict(.x,
      newdata = test
    ))
    accuracy <- purrr::map(predict, ~ table(.x, unlist(test[
      ,
      class_name
    ]))) %>%
      purrr::map(~ sum(diag(.x)) / sum(.x)) %>%
      unlist()
    log_acc <- log(accuracy / (1 - accuracy))
    log_acc[is.infinite(log_acc)] <- 1
    prob_weights <- log_acc / sum(log_acc)
    prob_weights <- ifelse(prob_weights < 0, 0, prob_weights)
    models <- rep(list(0), boots_size)
    boots_sample <- list(rep(boots_size))
    out_of_bag <- list(rep(boots_size))
    boots_index_row <- list(nrow(train)) %>% rep(boots_size)
    at_least_one <- NULL
    if (is.null(seed.bootstrap)) {
      while (is.null(at_least_one)) {
        boots_index_row_new <- purrr::map(
          boots_index_row,
          ~ sample(1:.x, .x, replace = TRUE)
        )
        boots_sample <- purrr::map(
          boots_index_row_new,
          ~ train[.x, ]
        )
        out_of_bag <- purrr::map(boots_index_row_new, ~ train[-unique(.x), ])
        if (any(unlist(lapply(boots_sample, function(x) {
          table(x[[class_name]]) == 0
        })))) {
          at_least_one <- NULL
        } else {
          at_least_one <- 1
        }
      }
    } else {
      set.seed(seed.bootstrap)
      while (is.null(at_least_one)) {
        boots_index_row_new <- purrr::map(
          boots_index_row,
          ~ sample(1:.x, .x, replace = TRUE)
        )
        boots_sample <- purrr::map(
          boots_index_row_new,
          ~ train[.x, ]
        )
        out_of_bag <- purrr::map(boots_index_row_new, ~ train[-unique(.x), ])
        if (any(unlist(lapply(boots_sample, function(x) {
          table(x[[class_name]]) == 0
        })))) {
          at_least_one <- NULL
        } else {
          at_least_one <- 1
        }
      }
    }
    random_kernel <- sample(kernel_type, boots_size, replace = TRUE, prob = prob_weights)
    if (automatic_tuning) {
      models <- purrr::map2(boots_sample, random_kernel, ~ kernlab::ksvm(formula,
        data = .x, type = "C-svc", kernel = if (.y == "vanilladot") {
          "polydot"
        } else if (.y == "cauchydot") {
          cauchydot()
        } else if (.y == "tdot") {
          tdot()
        } else {
          .y
        }, C = cost, kpar = if (.y == "laplacedot" || .y ==
          "rbfdot") {
          "automatic"
        } else if (.y == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.y == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.y == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    } else {
      models <- purrr::map2(boots_sample, random_kernel, ~ kernlab::ksvm(formula,
        data = .x, type = "C-svc", kernel = if (.y == "vanilladot") {
          "polydot"
        } else if (.y == "cauchydot") {
          cauchydot()
        } else if (.y == "tdot") {
          tdot()
        } else {
          .y
        }, C = cost, kpar = if (.y == "laplacedot") {
          list(sigma = gamma_lap)
        } else if (.y == "rbfdot") {
          list(sigma = gamma_rbf)
        } else if (.y == "polydot") {
          list(degree = 2, scale = poly_scale, offset = 0)
        } else if (.y == "cauchydot") {
          list(sigma = gamma_cau)
        } else if (.y == "tdot") {
          list(d = d_t)
        } else {
          list(degree = 1, scale = poly_scale, offset = 0)
        }
      ))
    }
    predict <- purrr::map(models, ~ kernlab::predict(.x, newdata = test))
    predict_oobg <- purrr::map2(models, out_of_bag, ~ kernlab::predict(.x,
      newdata = .y
    ))
    kernel_weight <- purrr::map2(predict_oobg, out_of_bag, ~ table(
      .x,
      unlist(.y[, class_name])
    )) %>% purrr::map_dbl(~ sum(diag(.x)) / sum(.x))

    kern_names_final <- kernel_type %>%
      as_tibble() %>%
      mutate(value = case_when(
        value == "rbfdot" ~ "RBF_Kern",
        value == "polydot" ~ "Pol_Kern",
        value == "laplacedot" ~ "LAP_Kern",
        value == "vanilladot" ~ "Lin_Kern",
        value == "cauchydot" ~ "CAU_Kern",
        value == "tdot" ~ "T_Kern"
      )) %>%
      pull(value)

    if (length(kern_names_final) == 2) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 3) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 4) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3],
          prob_weights[4]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 5) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3],
          prob_weights[4],
          prob_weights[5]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else if (length(kern_names_final) == 6) {
      model_result <- list(
        train = train, class_name = class_name,
        kernel_weight = kernel_weight, lambda_values = setNames(list(
          prob_weights[1],
          prob_weights[2],
          prob_weights[3],
          prob_weights[4],
          prob_weights[5],
          prob_weights[6]
        ), kern_names_final), model_params = list(
          class_name = class_name,
          boots_size = boots_size, cost = cost, gamma_rbf = gamma_rbf,
          gamma_lap = gamma_lap, degree = degree
        ), bootstrap_models = models,
        bootstrap_samples = boots_sample
      )
    } else {
      print("N??mero de Kernels n??o compat??vel")
    }

    attr(model_result, "class") <- "rm_model"
    return(model_result)
  }
}


predict_rm_meu <- function(mod, newdata, prob_model = T, agreement = FALSE) {
  if (prob_model == T) {
    models <- mod$bootstrap_models
    train <- mod$train
    class_name <- mod$class_name
    kernel_weight <- mod$kernel_weight
    predict_new <- purrr::map(models, ~ kernlab::predict(.x, newdata = newdata, type = "probabilities")[, 2])
    predict_df <- predict_new %>%
      unlist() %>%
      matrix(
        ncol = nrow(newdata),
        byrow = TRUE
      )
    predict_df_new <- purrr::map(seq(1:nrow(newdata)), ~ predict_df[
      ,
      .x
    ])
    pred_df_fct <- purrr::map(predict_df_new, ~ weighted.mean(.x, kernel_weight))
    return(pred_df_fct %>% unlist())
  } else {
    models <- mod$bootstrap_models
    train <- mod$train
    class_name <- mod$class_name
    kernel_weight <- mod$kernel_weight
    predict_new <- purrr::map(models, ~ kernlab::predict(.x,
      newdata = newdata
    ))
    predict_df <- predict_new %>%
      unlist() %>%
      matrix(
        ncol = nrow(newdata),
        byrow = TRUE
      )
    predict_df_new <- purrr::map(seq(1:nrow(newdata)), ~ predict_df[
      ,
      .x
    ])
    pred_df_fct <- purrr::map(predict_df_new, ~ ifelse(.x ==
      unlist(levels(train[[class_name]]))[1], 1, -1)) %>%
      purrr::map(~ .x / ((1 + 1e-10) - kernel_weight)^2) %>%
      purrr::map(sum) %>%
      purrr::map(sign) %>%
      purrr::map(~ ifelse(.x ==
        1, levels(dplyr::pull(train, class_name))[1], levels(unlist(train[
        ,
        class_name
      ]))[2])) %>%
      unlist() %>%
      as.factor()
    levels_class <- levels(train[[class_name]])
    pred_df_standard <- ifelse(predict_df == levels_class[[1]],
      1, -1
    )
    agreement_trees <- tcrossprod(pred_df_standard)
    agreement_trees <- (agreement_trees + agreement_trees[
      1,
      1
    ]) / (2 * agreement_trees[1, 1])
    avg_agreement <- mean(agreement_trees[lower.tri(agreement_trees,
      diag = FALSE
    )])
    if (agreement) {
      return(list(prediction = pred_df_fct, agreement = avg_agreement))
    } else {
      return(pred_df_fct)
    }
  }
}


predict_rm_meu_shap <- function(mod, newdata) {
  prob_model <- T
  agreement <- FALSE

  if (prob_model == T) {
    models <- mod$bootstrap_models
    train <- mod$train
    class_name <- mod$class_name
    kernel_weight <- mod$kernel_weight
    predict_new <- purrr::map(models, ~ kernlab::predict(.x, newdata = newdata, type = "probabilities")[, 2])
    predict_df <- predict_new %>%
      unlist() %>%
      matrix(
        ncol = nrow(newdata),
        byrow = TRUE
      )
    predict_df_new <- purrr::map(seq(1:nrow(newdata)), ~ predict_df[
      ,
      .x
    ])
    pred_df_fct <- purrr::map(predict_df_new, ~ weighted.mean(.x, kernel_weight))
    return(pred_df_fct %>% unlist())
  } else {
    models <- mod$bootstrap_models
    train <- mod$train
    class_name <- mod$class_name
    kernel_weight <- mod$kernel_weight
    predict_new <- purrr::map(models, ~ kernlab::predict(.x,
      newdata = newdata
    ))
    predict_df <- predict_new %>%
      unlist() %>%
      matrix(
        ncol = nrow(newdata),
        byrow = TRUE
      )
    predict_df_new <- purrr::map(seq(1:nrow(newdata)), ~ predict_df[
      ,
      .x
    ])
    pred_df_fct <- purrr::map(predict_df_new, ~ ifelse(.x ==
      unlist(levels(train[[class_name]]))[1], 1, -1)) %>%
      purrr::map(~ .x / ((1 + 1e-10) - kernel_weight)^2) %>%
      purrr::map(sum) %>%
      purrr::map(sign) %>%
      purrr::map(~ ifelse(.x ==
        1, levels(dplyr::pull(train, class_name))[1], levels(unlist(train[
        ,
        class_name
      ]))[2])) %>%
      unlist() %>%
      as.factor()
    levels_class <- levels(train[[class_name]])
    pred_df_standard <- ifelse(predict_df == levels_class[[1]],
      1, -1
    )
    agreement_trees <- tcrossprod(pred_df_standard)
    agreement_trees <- (agreement_trees + agreement_trees[
      1,
      1
    ]) / (2 * agreement_trees[1, 1])
    avg_agreement <- mean(agreement_trees[lower.tri(agreement_trees,
      diag = FALSE
    )])
    if (agreement) {
      return(list(prediction = pred_df_fct, agreement = avg_agreement))
    } else {
      return(pred_df_fct %>% unlist())
    }
  }
}
