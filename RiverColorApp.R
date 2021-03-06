
library(shiny)
library(sf)
library(leaflet)
library(tidyverse)
library(viridis)
library(ggthemes)
library(leafgl)

### load data
flowline<- readRDS("out/flowline_shiny.rds")  %>%
  st_cast("LINESTRING")

trend_annual <- readRDS("out/trend_shiny.rds")
sum_ID <- readRDS("out/sum_shiny.rds")
sum_ID_year <- readRDS("out/sum_year_shiny.rds")
sum_ID_month <- readRDS("out/sum_month_shiny.rds")
clust <- readRDS("out/clust_shiny.rds")
riverSR <- readRDS("out/riverSR_shiny.rds")

################################################
# Define UI for application 
ui <- fluidPage(
  
  tags$head(
    HTML(
      "
          <script>
          var socket_timeout_interval
          var n = 0
          $(document).on('shiny:connected', function(event) {
          socket_timeout_interval = setInterval(function(){
          Shiny.onInputChange('count', n++)
          }, 15000)
          });
          $(document).on('shiny:disconnected', function(event) {
          clearInterval(socket_timeout_interval)
          });
          </script>
          "
    )
  ),
   
  tags$head(tags$style(
    HTML(
      '.modal.in .modal-dialog{
        width:100%;
        height:1000px;
        margin:0px;
      }
      .modal-content{
        width:100%;
        height:100%;
      }'
    ))),
   # Application title
   titlePanel("The Color of US Rivers"),
   
   # Show maps
    fluidRow(
      column(8, 
             selectInput("mapInput", "Select Map Data", c("Modal Color (nm)", "Trends", "Seasonality")),
              
             #leafglOutput not working    
             leafglOutput(outputId = "map",  height = 600),
              
             mainPanel("Click on a river reach to change plots on the right")),
      
   # plot long-term trend, seasonal patternd, and colro distribution when click on a river
      column(4, 
             actionButton(inputId = "help_button", "Info", icon = icon("question-circle")),
          align = "right"),
   
      column(4, 
           
           plotOutput("plot_trend", height = 200),
           plotOutput("plot_season",   height = 200),
           plotOutput("plot_hist",  height = 200)),
   
   textOutput("keepAlive")
   
   )
)
##############################################
# Define server logic
server <- function(input, output, session) {

  output$keepAlive <- renderText({
    req(input$count)
    paste("keep alive ", input$count)
  })
  
  
  observe({
    if (!is.null(input$help_button) || LAUNCHING) {
      LAUNCHING <<- FALSE

      showModal(modalDialog(
        footer = modalButton("Go"),
        h1('Visualizing the color of rivers across the USA'),
        tags$p(
          tags$br(),
          tags$blockquote(
            "Rivers can appear as many different colors such as greens, blues, browns,
            and yellows. Water color, as perceived by the human eye, is intuitive,
            intergrative, and one of the oldest metrics of water quality.
            We can also measure water color using satellites such as Landsat. In a recent
            publication in Geophysical Research Letters, we used the Landsat record from 1984-2018
            to measure the color of all large rivers  in the continental USA.
            This website provides an interactive visualization of the color of rivers over space and time."),
          
          tags$br(),
          tags$blockquote(
            tags$b("By clicking on different rivers, you can visualize three main points:"),
            tags$ol(
              tags$li("A map of the most common color, or modal color. Click on a river to show the full 
                      color distribution over time quantified as dominant wavelength on the visible spectrum (nm)."),
              tags$li(
                "A map of the dominant seasonal pattern in river color. Click on a river to show a graph of the mean seasonal pattern.
                Summer red-shift means river color is closer to the red end of the visible spectrum, or
                yellower, in the summer and spring red-shifted means river color is yellower in the spring."),
              tags$li(
                "A map of the long-term trend. Click on a river to show the mean annual trend (colored line) and full data (gray circles).
                Red-shifted means the river is trending towards the red end of the spectrum over time.
                Blue-shifted means the river is trending towards the blue end of the spectrum over time. Steady 
                means there is little change in color over time. Variable means there is no trend and river color changes frequently."),
              
              tags$li("Click the info button in upper right corner to view this page again.")
            )
      
          ),
          tags$i(
            tags$p(
              "Authors: John Gardner, Xiao Yang, Simon Topp, Matthew Ross, Elizabeth Altenau, Tamlin Pavelsky"),
            p("Paper citation: Gardner J., Yang X., Topp S., Ross M., Altenau E., Pavelsky T. 2020. The Color of Rivers. Geophysical Research Letters"),
            p("Contact: gardner.john@pitt.edu")
            ),
          tags$b(
            tags$a(href = "https://gardnerlab.weebly.com/", "Gardner Hydrology Lab")
          )
          ),
        tags$hr(),
        tags$p(
          tags$b("Links"),
          tags$ol(
            tags$i(
              tags$a(href = "https://zenodo.org/record/4304567#.X86aQGhKiUk", " River Surface Reflectance Database (RiverSR)"),
              br()
            )),
         
          #insert link to paper later
             tags$ol(
             tags$i(
               tags$a(href = "https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2020GL088946", "Color of Rivers. GRL. 2020"),
               br()
               )),
          #insert link
          tags$ol(
            tags$i(
              tags$a(href = "https://www.epa.gov/waterdata/get-nhdplus-national-hydrography-dataset-plus-data", "National Hydrography Dataset (NHDPlusV2)"),
              br() )),
              
          tags$ol(
            tags$i(
              tags$p("NOTE: River geometries have been simplified."),
              br()

            ))
          )
        )
        )
    }
  }) 
  

# reactively create data for drop-down menu for selecting map data
  #NOTE: figure out how to make this faster with leafgl
  map_out <- reactive({

  x <- input$mapInput

  if (is.null(x)) {

    return(flowline %>%
             inner_join(sum_ID,  by="ID") %>%
             mutate(trend = dw_mode1)

      )

  } else if(x == "Modal Color (nm)") {

    return(flowline %>%
           inner_join(sum_ID,  by="ID") %>%
           mutate(trend = dw_mode1))


  } else if(x == "Trends") {

    return(flowline %>%
      left_join(trend_annual,  by="ID") %>%
        mutate(trend = ifelse(is.na(trend), "w/o enough data", trend))

      )

  } else if(x == "Seasonality") {

    return(flowline %>%
      left_join(clust, by="ID") %>%
        mutate(trend = ifelse(is.na(trend), "w/o enough data", trend))
  )
  }
  })

# make color palette reactive for each map. change back to map_out if neeed
pal <- reactive({

  x <- input$mapInput

  if (is.null(x)) {

    pal<-  colorNumeric(
      palette = "viridis",
      domain = map_out()$trend)

  } else if(x == "Modal Color (nm)") {

    pal<-  colorNumeric(
      palette = "viridis",
      domain = map_out()$trend)

  } else if(x == "Trends") {

    pal<- colorFactor(
      palette = c("green3", "gold2", "darkmagenta","gray50", "grey90"),
      domain = map_out()$trend)

  } else if(x == "Seasonality") {
    pal <- colorFactor(
      palette = c("green3","darkmagenta","darkorange1", "grey90"),
      domain = map_out()$trend)
  }
})

# plot map
  output$map <- renderLeaflet({
       leaflet(map_out()) %>%
       #clearShapes() %>%
       addProviderTiles(providers$Esri.WorldGrayCanvas, group = "Esri.WorldGrayCanvas") %>%
       addProviderTiles(providers$CartoDB.DarkMatter, group = "DarkMatter (CartoDB)") %>%
       addProviderTiles(providers$Esri.WorldTopoMap, group = "Esri.WorldTopoMap") %>%
       addProviderTiles(providers$Esri.WorldImagery, group = "Esri.WorldImagery") %>%
       addLayersControl(baseGroups = c("Esri.WorldGrayCanvas", "DarkMatter (CartoDB)", "Esri.WorldTopoMap",
                                       "Esri.WorldImagery"),
                        options = layersControlOptions(collapsed = TRUE, autoZIndex = T)) %>%
      setView(zoom=3.5, lat=42, lng=-98) %>%
      addGlPolylines(data=map_out(),
                    color = ~pal()(trend),
                    layerId = ~ID,
                   opacity=1,
                    weight=1, 
                 #  highlightOptions = highlightOptions(color = "white", weight = 4,
                  #                                     bringToFront = TRUE),
                   popup = paste("River name:", map_out()$GNIS_NA, "<br>",
                                 "Map data:", map_out()$trend, "<br>",
                                 "Reach ID:", map_out()$ID, "<br>",
                                 "Stream Order:", map_out()$StrmOrd))  %>%
                  
       addLegend("bottomleft", pal=pal(), values = ~trend, title="", opacity = 1)
  })
  
###################
# generate reactive data for ggplots

# trends
  ggplot_trend <- reactive({
    
    site <- input$map_glify_click$id
    
    # give plot some default data to plot on opening
    if (is.null(site)) {
      return(sum_ID_year[sum_ID_year$ID == 26739,])
      # make plot reactive to clicks  
    } else {
      return(sum_ID_year[sum_ID_year$ID == site,])
    }
  })

# seasonal pattern
  ggplot_season <- reactive({
    
    site <- input$map_glify_click$id
    
    # give plot some default data to plot on opening
    if (is.null(site)) {
      return(sum_ID_month[sum_ID_month$ID == 26739, ])
    # make plot reactive to clicks  
    } else{
      return(sum_ID_month[sum_ID_month$ID == site, ])
    }
  })

# full color distribution 
  ggplot_hist <- reactive({
    
    site <- input$map_glify_click$id
    
    # give plot some default data to plot on opening
    if (is.null(site)) {
      return(riverSR[riverSR$ID == 26739, ])
      # make plot reactive to clicks  
    } else{
      return(riverSR[riverSR$ID == site, ])
    }
  })

     output$plot_trend <- renderPlot({
       
    # color options
       cols <- c("Blue-shifted" = "green3", "Red-shifted"= "gold2", "Steady"="darkmagenta", 
                 "Variable"= "gray50", "w/o enough data" ="grey90")

       ggplot()+
         geom_point(data= ggplot_hist(),
                    aes(x=date, y=dw), color="lightgrey", alpha=0.5, size=1)  +
         geom_line(data = ggplot_trend(),
                   aes(x=as.Date(paste(as.character(year), 6, 1, sep = "-")), y=dw_mean, color=as.character(trend)), size=1.5)  +
         scale_x_date(breaks = as.Date(c("1985-01-01", "2000-01-01", "2015-01-01")),
                      date_labels = "%Y") +
         scale_color_manual(values=cols, name="") +
         theme_few() +
         ylab(expression(lambda~(nm))) +
         xlab("Year") +
         theme(legend.position = c(0.7, 0.98),
               legend.background = element_blank(),
               axis.text = element_text(size=14),
               axis.title = element_text(size=14),
               legend.text = element_text(size=11)) +
         ggtitle("Long-term trend")
     }) 
     
     output$plot_season <- renderPlot({

       cols2 <- c("Summer red-shift" = "darkorange1",  "Spring red-shift"="darkmagenta", 
                 "Aseasonal"= "springgreen3", "w/o enough data" ="grey90")
       
       ggplot(data = ggplot_season())+
         geom_point(aes(x=month, y=dw_mean, color=as.character(trend)), size=2.5)  +
         geom_smooth(method="loess", aes(x=month, y=dw_mean, color=as.character(trend) ), se=F)  +
         scale_color_manual(values=cols2, name="") +
         scale_x_continuous(breaks=seq(1,12,1), name = "Month") +
         theme_few() +
         ylab(expression(Mean~lambda~(nm))) +
         theme(legend.position = c(0.7, 0.98),
               legend.background = element_blank(),
               axis.text = element_text(size=14),
               axis.title = element_text(size=14),
               legend.text = element_text(size=11)) +
         ggtitle("Seasonal pattern")
     }) 
     
     output$plot_hist <- renderPlot({
       
       ggplot(data = ggplot_hist())+
         geom_histogram(aes(dw), fill="grey", color="black")  +
         xlim(450,600) +
         theme_few() +
         ylab("Count") +
         xlab(expression(lambda~(nm))) +
         theme(axis.text = element_text(size=14),
              axis.title = element_text(size=14)) +
         ggtitle("Color Distribution")
     })
     
}

# Run the application 
shinyApp(ui = ui, server = server)

###############################################################################


