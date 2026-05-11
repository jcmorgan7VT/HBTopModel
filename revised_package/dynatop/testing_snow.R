system("cd /Users/johnmorgan/Downloads/dynatop_snow && rm -f src/*.o src/*.so")

rm(list=ls())
devtools::clean_dll()
setwd("/Users/johnmorgan/Downloads/dynatop_snow")
#devtools::install(pacPath)
#install.packages("bookdown")
pacPath <- file.path("/Users/johnmorgan/Downloads/dynatop_snow") ## path of the folder containing the package DESCRIPTION file
## the <package>::<function> format used below calls installed R packages without fully attaching then to the workspace

Rcpp::compileAttributes(pacPath) ## compile the attributes of the C++/R linkage
devtools::document(pacPath) ## compile the function documentation and NAMESPACE
devtools::check(pacPath, vignettes = FALSE) ## check the package by building it and running tests
## The check function produces significant amounts of output. Significant notes, warning and errors are repeated at the end
devtools::build(pacPath, vignettes = FALSE) ## If there are no warnings or errors in the check then call this to build the package

devtools::load_all(pacPath) ## attach the revised package
# save swindale with temp column
#save(Swindale, file = "./data/Swindale_orig.rda")

# before compiling- fix the testing dataset
data(Swindale)
obs <- Swindale$obs
obs$temp <- 10
model <- Swindale$model
####### add snow params ######
# Assuming 'mdl' is your existing, unmodified model list 
# (e.g., extracted from something like Swindale$model)
mdl <- model
for (i in seq_along(mdl$hru)) {
  
  # 1. Add the snow parameters
  # The type MUST be "hbv" and parameters MUST be named T_T, C_f, and C_wh
  mdl$hru[[i]]$snow <- list(
    type = "hbv",
    parameters = c(
      T_T = 0.0,   # Threshold temperature (e.g., 0 degrees C)
      C_f = 2.5,   # Degree-day melt factor 
      C_wh = 0.1   # Water holding capacity of the snowpack (e.g., 10%)
    )
  )
  
  # 2. Add the temperature linkage
  # The 'name' must exactly match the temperature column name in the 'obs' 
  # data frame you will feed to ctch_mdl$add_data(obs) later.
  mdl$hru[[i]]$temp <- list(
    name = "Temp_Series_1" # Replace with your actual temperature series name
  )
  
  # 3. Expand the initial states vector
  # Append s_snow and s_liquid to the existing 6 states so C++ doesn't crash
  mdl$hru[[i]]$states <- c(
    mdl$hru[[i]]$states, 
    s_snow = 0.0, 
    s_liquid = 0.0
  )
}
###### bigger data replacement ######
# 1. Load the existing built-in dataset
load("data/Swindale.rda") # or data/Swindale.rda, whichever exists in the data/ folder

# 2. Patch the HRUs with snow parameters, temp linkages, and expanded states
for (i in seq_along(Swindale$model$hru)) {
  
  # A. Add the snow parameters
  Swindale$model$hru[[i]]$snow <- list(
    type = "hbv",
    parameters = c(T_T = 0.0, C_f = 2.5, C_wh = 0.1)
  )
  
  # B. Add the temp linkage 
  # Note: The original precip linkage uses 'name' and 'fraction'
  # We will map it to a dummy "temp_series"
  Swindale$model$hru[[i]]$temp <- list(
    name = "temp_series",
    fraction = 1.0
  )
  
  # C. Expand the states to include s_snow and s_liquid
  Swindale$model$hru[[i]]$states <- c(
    Swindale$model$hru[[i]]$states, 
    s_snow = 0, 
    s_liquid = 0
  )
}

# 3. Add a dummy temperature time series to the observations
# Swindale$obs is likely an xts object or data frame.
# We'll just add a constant 5.0 degrees C for the tests to run successfully
Swindale$obs$temp_series <- 5.0

# 4. Overwrite the package dataset with the patched version
save(Swindale, file = "data/Swindale.rda", compress = "xz")
# Alternatively, if you use the 'usethis' package, you can run:
# usethis::use_data(Swindale, overwrite = TRUE)

#######
Swindale <- list("model" = mdl, "obs" = obs)
save(Swindale, file = "./data/Swindale.rda")

data(Swindale)
obs <- Swindale$obs
obs$temp <- 25

dt <- dynatop$new(Swindale$model$hru)$add_data(obs)

dt$initialise()$sim(Swindale$model$output_flux)
out <- dt$get_mass_errors()[,6]
plot(dt$get_output())

tmp <- max(abs(dt$get_mass_errors()[,6]))
testthat::expect_lt( tmp, 1e-6 )
#Try running with snow