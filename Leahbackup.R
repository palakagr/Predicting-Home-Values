# Load Libraries
library(tidyverse)
library(sf)
library(spdep)
library(caret)
library(ckanr)
library(FNN)
library(grid)
library(gridExtra)
library(ggcorrplot)
library(jtools)  
library(viridis)
library(fastDummies)

options(scipen=999)
options(tigris_class = "sf")

# Themes and Functions
mapTheme <- function(base_size = 12) {
  theme(
    text = element_text( color = "black"),
    plot.title = element_text(size = 14,colour = "black"),
    plot.subtitle=element_text(face="italic"),
    plot.caption=element_text(hjust=0),
    axis.ticks = element_blank(),
    panel.background = element_blank(),axis.title = element_blank(),
    axis.text = element_blank(),
    axis.title.x = element_blank(),
    axis.title.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(colour = "black", fill=NA, size=2)
  )
}

plotTheme <- function(base_size = 12) {
  theme(
    text = element_text( color = "black"),
    plot.title = element_text(size = 14,colour = "black"),
    plot.subtitle = element_text(face="italic"),
    plot.caption = element_text(hjust=0),
    axis.ticks = element_blank(),
    panel.background = element_blank(),
    panel.grid.major = element_line("grey80", size = 0.1),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(colour = "black", fill=NA, size=2),
    strip.background = element_rect(fill = "grey80", color = "white"),
    strip.text = element_text(size=12),
    axis.title = element_text(size=12),
    axis.text = element_text(size=10),
    plot.background = element_blank(),
    legend.background = element_blank(),
    legend.title = element_text(colour = "black", face = "italic"),
    legend.text = element_text(colour = "black", face = "italic"),
    strip.text.x = element_text(size = 14)
  )
}

palette5 <- c("#25CB10", "#5AB60C", "#8FA108",   "#C48C04", "#FA7800")

qBr <- function(df, variable, rnd) {
  if (missing(rnd)) {
    as.character(quantile(round(df[[variable]],0),
                          c(.01,.2,.4,.6,.8), na.rm=T))
  } else if (rnd == FALSE | rnd == F) {
    as.character(formatC(quantile(df[[variable]]), digits = 3),
                 c(.01,.2,.4,.6,.8), na.rm=T)
  }
}

q5 <- function(variable) {as.factor(ntile(variable, 5))}

nn_function <- function(measureFrom,measureTo,k) {
  measureFrom_Matrix <- as.matrix(measureFrom)
  measureTo_Matrix <- as.matrix(measureTo)
  nn <-   
    get.knnx(measureTo, measureFrom, k)$nn.dist
  output <-
    as.data.frame(nn) %>%
    rownames_to_column(var = "thisPoint") %>%
    gather(points, point_distance, V1:ncol(.)) %>%
    arrange(as.numeric(thisPoint)) %>%
    group_by(thisPoint) %>%
    summarize(pointDistance = mean(point_distance)) %>%
    arrange(as.numeric(thisPoint)) %>% 
    dplyr::select(-thisPoint) %>%
    pull()
  
  return(output)  
}

# Wrangle Miami Data
MiamiDF <- st_read("C:/Users/owner160829a/Documents/GitHub/MUSA-508-Assignment2/studentsData.geojson")

MiamiDF <- st_transform(MiamiDF,'ESRI:102658')

MiamiDF <- dplyr::select(MiamiDF,-saleQual,-WVDB,-HEX,-GPAR,-County.2nd.HEX,
                         -County.Senior,-County.LongTermSenior,-County.Other.Exempt,
                         -City.2nd.HEX,-City.Senior,-City.LongTermSenior,
                         -City.Other.Exempt,-MillCode,-Land.Use,
                         -Owner1,-Owner2,-Mailing.Address,-Mailing.City,
                         -Mailing.State,-Mailing.Zip,-Mailing.Country,-Legal1,
                         -Legal2,-Legal3,-Legal4,-Legal5,-Legal6 )

# Wrangle XF Columns
MiamiDF<- mutate(MiamiDF,XFs=paste(XF1,XF2,XF3, sep=",")) %>%
  dummy_cols(select_columns="XFs", split=",")

MiamiDF <- st_as_sf(MiamiDF)

# Wrangle Pool Columns
MiamiDF$LuxuryPool<- ifelse(MiamiDF$`XFs_Luxury Pool - Best`==1 | MiamiDF$`XFs_Luxury Pool - Better`==1 | MiamiDF$`XFs_Luxury Pool - Good.`==1,1,0)

MiamiDF$'3to6ftPool' <- ifelse(MiamiDF$`XFs_Pool COMM AVG 3-6' dpth`==1|MiamiDF$`XFs_Pool COMM BETTER 3-6' dpth`==1,1,0)

MiamiDF$'3to8ftPool' <- ifelse(MiamiDF$`XFs_Pool 6' res BETTER 3-8' dpth`==1|MiamiDF$`XFs_Pool 6' res AVG 3-8' dpth`==1,1,0)

MiamiDF <- rename(MiamiDF,`8ftres3to8ftPool`=`XFs_Pool 8' res BETTER 3-8' dpth`)

MiamiDF <- rename(MiamiDF, Whirpool=`XFs_Whirlpool - Attached to Pool (whirlpool area only)`)

MiamiDF <- rename(MiamiDF,`2to4ftPool`= `XFs_Pool - Wading - 2-4' depth`)

MiamiDF <- select(MiamiDF,-"XFs_Pool 6' res BETTER 3-8' dpth",
                       -"XFs_Pool 6' res AVG 3-8' dpth",-"XFs_Luxury Pool - Best",
                       -"XFs_Luxury Pool - Better",-"XFs_Luxury Pool - Good.",
                       -"XFs_Pool COMM AVG 3-6' dpth",-"XFs_Pool COMM BETTER 3-6' dpth",
                       -"XFs_large",-"XFs_elec",-"XFs_plumb",-"XFs_Tiki Hut - Standard Thatch roof w/poles",
                       -"XFs_Tiki Hut - Good Thatch roof w/poles & electric",-"XFs_Tiki Hut - Better Thatch roof",
                       -"XFs_Bomb Shelter - Concrete Block",-"XFs_Tennis Court - Asphalt or Clay" ) 

# Wrangle Fence Columns
MiamiDF$Fence <- ifelse(MiamiDF$`XFs_Aluminum Modular Fence`==1| MiamiDF$`XFs_Wood Fence`==1|MiamiDF$`XFs_Chain-link Fence 4-5 ft high`==1|MiamiDF$`XFs_Wrought Iron Fence`==1|MiamiDF$`XFs_Chain-link Fence 6-7 ft high`==1|MiamiDF$`XFs_Concrete Louver Fence`==1|MiamiDF$`XFs_Chain-link Fence 8-9 ft high`==1|MiamiDF$`XFs_Glass fences in backyard applications`==1,1,0)

MiamiDF <- select(MiamiDF,-"XFs_Aluminum Modular Fence",
                  -"XFs_Wood Fence",-"XFs_Chain-link Fence 4-5 ft high",
                  -"XFs_Wrought Iron Fence",-"XFs_Chain-link Fence 6-7 ft high",
                  -"XFs_Concrete Louver Fence",-"XFs_Chain-link Fence 8-9 ft high",
                  -"XFs_Glass fences in backyard applications")

# Wrangle Patio Columns
MiamiDF$Patio <- ifelse(MiamiDF$`XFs_Patio - Concrete Slab`==1|MiamiDF$`XFs_Patio - Concrete Slab w/Roof Aluminum or Fiber`==1|MiamiDF$`XFs_Patio - Wood Deck`==1|MiamiDF$`XFs_Patio - Marble`==1|MiamiDF$`XFs_Patio - Terrazzo`==1|MiamiDF$`XFs_Patio - Screened over Concrete Slab`==1|MiamiDF$`XFs_Patio - Exotic hardwood`==1|MiamiDF$`XFs_Patio - Concrete stamped or stained`==1,1,0)

MiamiDF <-select(MiamiDF,-"XFs_Patio - Concrete Slab",-"XFs_Patio - Concrete Slab w/Roof Aluminum or Fiber",
                 -"XFs_Patio - Wood Deck",-"XFs_Patio - Marble",
                 -"XFs_Patio - Terrazzo",-"XFs_Patio - Screened over Concrete Slab",
                 -"XFs_Patio - Exotic hardwood",-"XFs_Patio - Concrete stamped or stained")

# Create Categorical Variables
MiamiDF$YearCat <- cut(MiamiDF$YearBuilt, c(1900,1909,1919,1929,1939,1949,
                                                      1959,1969,1979,1989,1999,2009,2019))

MiamiDF$BedCat <- cut(MiamiDF$Bed,breaks=c(0:8,Inf), right=FALSE, labels=c(0:7,"8+"))

# Join Neighborhood Data
Neighborhoods <- st_read("https://opendata.arcgis.com/datasets/2f54a0cbd67046f2bd100fb735176e6c_0.geojson")

Neighborhoods <- st_transform(Neighborhoods,'ESRI:102658')

MiamiDF <- st_join(MiamiDF, Neighborhoods, join = st_intersects) 

# Remove Challenge Houses
MiamiDFKnown <- MiamiDF[!(MiamiDF$SalePrice==0),]
  
# Map House Sales and Neighborhoods
ggplot() +
  geom_sf(data=Neighborhoods)+
  geom_sf(data=MiamiDF)

ggplot() +
  geom_sf(data = Neighborhoods, fill = "grey40") +
  geom_sf(data = MiamiDFKnown, aes(colour = q5(SalePrice)), 
          show.legend = "point", size = 1) +
  scale_colour_manual(values=palette5,
                      labels=qBr(MiamiDFKnown,"SalePrice"),
                      name="Quintile\nBreaks") +
  labs(title="Sale Price, Miami") +
  mapTheme()

# Correlation Matrices
numericVars <- 
  select_if(st_drop_geometry(MiamiDFKnown), is.numeric) %>% na.omit() %>%
  select(SalePrice, Land, Bldg, Total, Assessed, City.Taxable, AdjustedSqFt,
         LotSize, Bed, Bath, Stories, Units, YearBuilt, EffectiveYearBuilt,
         LivingSqFt, ActualSqFt,Patio,Fence,`3to8ftPool`,`3to6ftPool`,`LuxuryPool`)

ggcorrplot(
  round(cor(numericVars), 1), 
  p.mat = cor_pmat(numericVars),
  colors = c("#25CB10", "white", "#FA7800"),
  type="lower",
  insig = "blank") +  
  labs(title = "Correlation across numeric variables") 

dummyVars <- select_if(st_drop_geometry(MiamiDFKnown), is.numeric) %>% 
  na.omit() %>% select("SalePrice", "3to8ftPool",
                       "3to6ftPool","LuxuryPool",
                       "8ftres3to8ftPool",
                       "Whirpool","2to4ftPool",
                       "XFs_Central A/C (Aprox 400 sqft/Ton)")

ggcorrplot(
  round(cor(dummyVars), 1), 
  p.mat = cor_pmat(dummyVars),
  colors = c("#25CB10", "white", "#FA7800"),
  type="lower",
  insig = "blank") +  
  labs(title = "Correlation across XF variables")   

# Regression Adj R-squared=.7282
reg <- lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
             dplyr::select(SalePrice, Bed, Bath, Stories, YearBuilt,LivingSqFt))
summ(reg)
summary(reg)

## Regression with Neighborhoods Adj R-squared=.7316
reg2 <-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
            dplyr::select(SalePrice, Bed, Bath, Stories, YearBuilt,LivingSqFt,LABEL))
summ(reg2)
summary(reg2)

## Regression with XFs and Neighborhoods Adj. R-squared .7556
reg3 <-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
            dplyr::select(SalePrice, Bed, Bath, Stories, YearBuilt,
                          LivingSqFt,LABEL,Patio,Fence,`3to8ftPool`,
                          `3to6ftPool`,`LuxuryPool`))
summ(reg3)
summary(reg3)

# Creating Year Built Categories A rsquared=.7631
## YearCat not stat sig
MiamiDFKnown$YearCat <- cut(MiamiDFKnown$YearBuilt, c(1900,1909,1919,1929,1939,1949,
                                                     1959,1969,1979,1989,1999,2009,2019))

reg4 <-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
            dplyr::select(SalePrice, Bed, Bath, Stories, YearCat,LivingSqFt,
                          LABEL,Patio,Fence,`3to8ftPool`,
                          `3to6ftPool`,`LuxuryPool`))
summ(reg4)
summary(reg4)

# Creating Bed Categories Adj R squared=.7669
## BedCat no longer statistically significant
reg5 <-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
            dplyr::select(SalePrice, BedCat, Bath, Stories, YearCat,LivingSqFt,
                          LABEL,Patio,Fence,`3to8ftPool`,
                          `3to6ftPool`,`LuxuryPool`))
summ(reg5)
summary(reg5)

# External Model Validation
## set random seed
set.seed(121491)

# get index for training sample
#inTrain <- caret::createDataPartition(
 # y = MiamiDFKnown$SalePrice, 
 # p = .60, list = FALSE)

## trying to fix s.t.
inTrain <- caret::createDataPartition(
  y = paste(MiamiDFKnown$LABEL,MiamiDFKnown$BedCat), 
  p = .60, list = FALSE)


# split data into training and test, before comma is row, after comma is column
Miami.training <- MiamiDFKnown[inTrain,] 
Miami.test     <- MiamiDFKnown[-inTrain,]  

# Regression
## Add whirpool?
reg6 <- lm(SalePrice ~ ., data = st_drop_geometry(Miami.training) %>% 
             dplyr::select(SalePrice, BedCat, Bath, Stories, YearCat,LivingSqFt,
                                         LABEL,Patio,Fence,`3to8ftPool`,
                                         `3to6ftPool`,`LuxuryPool`))


# Run this a number of times to see Adjusted R2
## Old numbers before adding patio and fence .7686, .8184, .8139, .8469, .8411 
## New numbers .8162, .808, .7846, .7817, .7848, .7725 
summary(reg6)

## predicting on new data
### need help here
reg6_predict <- predict(reg6, newdata = Miami.test)

Miami.test <-
  Miami.test %>%
  mutate(SalePrice.Predict = predict(reg6, Miami.test),
         SalePrice.Error = SalePrice.Predict - SalePrice,
         SalePrice.AbsError = abs(SalePrice.Predict - SalePrice),
         SalePrice.APE = (abs(SalePrice.Predict - SalePrice)) / SalePrice.Predict) 

##%>%
  ##filter(SalePrice < 5000000)

mean(Miami.test$SalePrice.AbsError, na.rm = T)
mean(Miami.test$SalePrice.APE, na.rm = T)

### Try to figure out how to make a histogram of AbsError, see section 3.4.1
hist(Miami.test$`SalePrice.AbsError`,xlab="Sales Price Absolute Error",
     breaks=50, col="purple")

# Measure Generalizability
## Mean Square Error train and test
rmse.train <- caret::MAE(predict(reg6), Miami.training$SalePrice)
rmse.test  <- caret::MAE(reg6_predict, Miami.test$SalePrice)

# Problem Here, getting Test MAE: NA
cat("Train MAE: ", as.integer(rmse.train), " \n","Test MAE: ", as.integer(rmse.test))

# Plotting accuracy metrics
preds.train <- data.frame(pred   = predict(reg6),
                          actual = Miami.training$SalePrice,
                          source = "training data")
preds.test  <- data.frame(pred   = reg6_predict,
                          actual = Miami.test$SalePrice,
                          source = "testing data")
preds <- rbind(preds.train, preds.test)

ggplot(preds, aes(x = pred, y = actual, color = source)) +
  geom_point() +
  geom_smooth(method = "lm", color = "green") +
  geom_abline(color = "orange") +
  coord_equal() +
  theme_bw() +
  facet_wrap(~source, ncol = 2) +
  labs(title = "Comparing predictions to actual values",
       x = "Predicted Value",
       y = "Actual Value") +
  theme(
    legend.position = "none"
  )

# Cross Validation
fitControl <- trainControl(method = "cv", 
                           number = 10,
                           # savePredictions differs from book
                           savePredictions = TRUE)

set.seed(717)

# for k-folds CV
reg.cv <- 
  train(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
          dplyr::select(SalePrice, BedCat, Bath, Stories, YearCat,LivingSqFt,
        LABEL,Patio,Fence,`3to8ftPool`,
        `3to6ftPool`,`LuxuryPool`,`Whirpool`),
        method = "lm", 
        trControl = fitControl, 
        na.action = na.pass)

reg.cv

reg.cv$resample

reg.cv$resample %>% 
  pivot_longer(-Resample) %>% 
  mutate(name = as.factor(name)) %>% 
  ggplot(., aes(x = name, y = value, color = name)) +
  geom_jitter(width = 0.1) +
  facet_wrap(~name, ncol = 3, scales = "free") +
  theme_bw() +
  theme(
    legend.position = "none"
  )
### Add historgram for MAE

# extract predictions from CV object
cv_preds <- reg.cv$pred
# compare number of observations between data sets
nrow(MiamiDFKnown)
nrow(cv_preds)

## Create dataset with "out of fold" predictions and original data
### This isn't working

MiamiDFKnown <- MiamiDFKnown %>%
  mutate(pred = predict(reg.cv, .)) %>%  #get a prediction for each row
  mutate(error = pred - SalePrice)    #calculate errors

##map_preds <- MiamiDFKnown %>% 
 ## rowid_to_column(var = "rowIndex") %>% 
 ## left_join(cv_preds, by = "rowIndex") %>% 
  ##mutate(SalePrice.AbsError = abs(pred - SalePrice)) %>% 
 ## cbind(st_coordinates(.))

# weird CRS fix to boston.sf
st_crs(map_preds) <- st_crs(Neighborhoods)

# plot errors on a map
ggplot() +
  geom_sf(data = Neighborhoods, fill = "grey40") +
  geom_sf(data = MiamiDFKnown, aes(colour = q5(error)),
          show.legend = "point", size = 1) +
  scale_colour_manual(values = palette5,
                      labels=qBr(MiamiDFKnown,"error"),
                      name="Quintile\nBreaks") +
  labs(title="Absolute sale price errors on the OOF set",
       subtitle = "OOF = 'Out Of Fold'") +
  mapTheme()

# XF Features More Wrangling
## Ignore this stuff
colnames(MiamiDF)

###677
table(MiamiDF$"XFs_Pool 6' res BETTER 3-8' dpth")
###165
table(MiamiDF$"XFs_Pool 8' res BETTER 3-8' dpth")
### 115
table(MiamiDF$"XFs_Pool 6' res AVG 3-8' dpth")
### 2
table(MiamiDF$"XFs_Luxury Pool - Best")
### 5
table(MiamiDF$"XFs_Luxury Pool - Better")
### 31
table(MiamiDF$"XFs_Luxury Pool - Good.")
### 5
table(MiamiDF$"XFs_Pool - Wading - 2-4' depth")
### 120
table(MiamiDF$"XFs_Whirlpool - Attached to Pool (whirlpool area only)")
### 10
table(MiamiDF$"XFs_Pool COMM AVG 3-6' dpth")
### 2
table(MiamiDF$"XFs_Pool COMM BETTER 3-6' dpth")

PoolCorr <- select_if(st_drop_geometry(MiamiDF), is.numeric) %>% 
  na.omit() %>% select("SalePrice","XFs_Pool 6' res BETTER 3-8' dpth",
                       "XFs_Pool 8' res BETTER 3-8' dpth","XFs_Pool 6' res AVG 3-8' dpth",
                       "XFs_Luxury Pool - Best","XFs_Luxury Pool - Better",
                       "XFs_Luxury Pool - Good.","XFs_Whirlpool - Attached to Pool (whirlpool area only)",
                       "XFs_Pool COMM AVG 3-6' dpth","XFs_Pool COMM BETTER 3-6' dpth")

ggcorrplot(
  round(cor(PoolCorr), 1), 
  p.mat = cor_pmat(PoolCorr),
  colors = c("#25CB10", "white", "#FA7800"),
  type="lower",
  insig = "blank") +  
  labs(title = "Pool Types")   

poolreg <-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>% 
               dplyr::select("SalePrice","XFs_Pool 6' res BETTER 3-8' dpth",
                             "XFs_Pool 8' res BETTER 3-8' dpth","XFs_Pool 6' res AVG 3-8' dpth",
                             "XFs_Luxury Pool - Best","XFs_Luxury Pool - Better",
                             "XFs_Luxury Pool - Good.","XFs_Whirlpool - Attached to Pool (whirlpool area only)",
                             "XFs_Pool COMM AVG 3-6' dpth","XFs_Pool COMM BETTER 3-6' dpth","LABEL"))
summ(poolreg)
summary(poolreg)

## Fences 
FenceCorr <- select_if(st_drop_geometry(MiamiDF), is.numeric) %>% 
  na.omit() %>% select("SalePrice","XFs_Aluminum Modular Fence","XFs_Wood Fence",
                       "XFs_Chain-link Fence 4-5 ft high", "XFs_Wrought Iron Fence",
                       "XFs_Chain-link Fence 6-7 ft high", "XFs_Concrete Louver Fence",
                       "XFs_Chain-link Fence 8-9 ft high","XFs_Glass fences in backyard applications")

ggcorrplot(
  round(cor(FenceCorr), 1), 
  p.mat = cor_pmat(FenceCorr),
  colors = c("#25CB10", "white", "#FA7800"),
  type="lower",
  insig = "blank") +  
  labs(title = "Fence Types")   

fencereg <-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>%
               dplyr::select("SalePrice","XFs_Aluminum Modular Fence","XFs_Wood Fence",
                             "XFs_Chain-link Fence 4-5 ft high", "XFs_Wrought Iron Fence",
                             "XFs_Chain-link Fence 6-7 ft high", "XFs_Concrete Louver Fence",
                             "XFs_Chain-link Fence 8-9 ft high","XFs_Glass fences in backyard applications","LABEL"))
summ(fencereg)
summary(fencereg)

MiamiDFKnown$Fence <- ifelse(MiamiDFKnown$`XFs_Aluminum Modular Fence`==1|MiamiDFKnown$`XFs_Wood Fence`==1|MiamiDFKnown$`XFs_Chain-link Fence 4-5 ft high`==1|MiamiDFKnown$`XFs_Wrought Iron Fence`==1|MiamiDFKnown$`XFs_Chain-link Fence 6-7 ft high`==1|MiamiDFKnown$`XFs_Concrete Louver Fence`==1|MiamiDFKnown$`XFs_Chain-link Fence 8-9 ft high`==1|MiamiDFKnown$`XFs_Glass fences in backyard applications`==1,1,0)

fencereg2<-lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFKnown) %>%
                dplyr::select("SalePrice","Fence","LABEL"))
summ(fencereg2)
summary(fencereg2)

FenceCorr2 <- select_if(st_drop_geometry(MiamiDFKnown), is.numeric) %>% 
  na.omit() %>% select("SalePrice","XFs_Aluminum Modular Fence","XFs_Wood Fence",
                       "XFs_Chain-link Fence 4-5 ft high", "XFs_Wrought Iron Fence",
                       "XFs_Chain-link Fence 6-7 ft high", "XFs_Concrete Louver Fence",
                       "XFs_Chain-link Fence 8-9 ft high","XFs_Glass fences in backyard applications","Fence")

ggcorrplot(
  round(cor(FenceCorr2), 1), 
  p.mat = cor_pmat(FenceCorr2),
  colors = c("#25CB10", "white", "#FA7800"),
  type="lower",
  insig = "blank") +  
  labs(title = "Fence Types")   

## Patios
PatioCorr <- select_if(st_drop_geometry(MiamiDF), is.numeric) %>% 
  na.omit() %>% select("SalePrice","XFs_Patio - Concrete Slab","XFs_Patio - Concrete Slab w/Roof Aluminum or Fiber",
                       "XFs_Patio - Wood Deck", "XFs_Patio - Marble",
                       "XFs_Patio - Terrazzo", "XFs_Patio - Screened over Concrete Slab",
                       "XFs_Patio - Exotic hardwood","XFs_Patio - Concrete stamped or stained")

ggcorrplot(
  round(cor(PatioCorr), 1), 
  p.mat = cor_pmat(PatioCorr),
  colors = c("#25CB10", "white", "#FA7800"),
  type="lower",
  insig = "blank") +  
  labs(title = "Patio Types") 

              
#Adding Spatial Features
## Beaches
Beaches<- st_read("https://opendata.arcgis.com/datasets/9e30807e3efd44f3b16ab8d3657249f2_0.geojson")

Beaches <- Beaches %>% 
  st_as_sf(coords = c("Lon", "Lat"), crs = 4326, agr = "constant") %>%
  st_transform('ESRI:102658')

ggplot() +
  geom_sf(data = Neighborhoods, fill = "grey40") +
  geom_sf(data = Beaches, aes(color="pink"), 
          show.legend = "point", size = 1) +
  mapTheme()

## Shoreline
Shoreline <- st_read("https://opendata.arcgis.com/datasets/58386199cc234518822e5f34f65eb713_0.geojson")
Shoreline<- st_transform(Shoreline,'ESRI:102658')

ggplot() +
  geom_sf(data = Neighborhoods, fill = "grey40") +
  geom_sf(data = Shoreline)

## Distance to shoreline

MiamiDFShoreline <- mutate(MiamiDF, distancetoshore=(st_distance(MiamiDF, Shoreline)))

## Something weird going on with this regression
regshoreline <- lm(SalePrice ~ ., data = st_drop_geometry(MiamiDFShoreline) %>% 
            dplyr::select(SalePrice, distancetoshore))
summ(regshoreline)
summary(regshoreline)

# School Attendance Areas
## Doesn't include Miami Beach
## Something is wrong with projection
ElementarySchool <- st_read("https://opendata.arcgis.com/datasets/19f5d8dcd9714e6fbd9043ac7a50c6f6_0.geojson")
ElementarySchool<- st_transform(ElementarySchool,'ESRI:102658') %>%
  select(-FID,-ID,-ZIPCODE,-PHONE,-REGION,-ID2,-FLAG,-CREATEDBY,-CREATEDDATE,-MODIFIEDBY,-MODIFIEDDATE)
ElementarySchool<-filter(ElementarySchool,CITY==c("Miami","MiamiBeach"))

ggplot() +
  geom_sf(data = ElementarySchool, fill = "grey40") +
  geom_sf(data = MiamiDF)+
  geom_sf(data = Neighborhoods)
  
MiamiDFSchool<-st_join(MiamiDF, ElementarySchool, join = st_intersects)
