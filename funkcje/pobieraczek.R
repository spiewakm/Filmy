library(XML)
library(rvest)
library(dplyr)
library(RCurl)
library(stringi)

from_full_cast_n_crew <- function( link, sep="," ){
      tytuly_kolumn <- c("DirectedBy","Cast","Writing","ProducedBy","MusicBy","CinematographyBy")
      
      link <- paste0(link, ifelse(stri_sub(link,-1)=="/", "", "/"), "fullcredits") 
      tables <- link %>% readHTMLTable          # wczytanie wszystkich tabel z podstrony Cast&Crew    
      n <- length(tables)
      headers <- link %>%                       # wczytanie naglowkow tabelek
            html %>% html_nodes("h4") %>% html_text %>% "["(1:n)
      # Zamieniam najistotniejsze nazwy, aby byly uniwersalne dla kazdej
      # pobranej tabelki (czasami dopisuja jakies pierdoly w nawiasach)
      headers[ stri_detect_regex(headers, "Directed") ] <- tytuly_kolumn[1]
      headers[ stri_detect_regex(headers, "Cast[^\\p{L}]") ] <- tytuly_kolumn[2]   # uwaga, zeby Casting By nie zamienilo na Cast!
      headers[ stri_detect_regex(headers, "Writing") ] <- tytuly_kolumn[3]
      headers[ stri_detect_regex(headers, "Produced") ] <- tytuly_kolumn[4]
      headers[ stri_detect_regex(headers, "Music [B|b]y") ] <- tytuly_kolumn[5]
      headers[ stri_detect_regex(headers, "Cinematography") ] <- tytuly_kolumn[6]  
      # Nadanie nazw tabelom:
      names(tables) <- headers
      tables$Cast <- tables$Cast[,-1]      # pierwsza kolumna Cast jest pusta, bo jest na zdjecia.
      # Wydobycie *pierwszych* kolumn tabel: interesuja nas tylko nazwiska aktorow, a nie np. ze Eddie Murphy byl glosem Osla.
      info_z_cast_crew <- lapply(tytuly_kolumn, function(h){
            zawartosc_tabelki <- as.character(tables[[h]][,1])
            paste0(zawartosc_tabelki[nchar(zawartosc_tabelki)>1],collapse = sep)
            # nchar>1 dlatego, ze czasem \n bierze jako char dlugosci=1.
      })
      names(info_z_cast_crew) <- tytuly_kolumn
      return(as.data.frame(info_z_cast_crew))
}

# info z nodesow
from_main_page <- function( link, sep="," ){
      # 1. wydlubanie informacji ze strony glownej filmu nodesami:
      all_nodes <- c(title=".header .itemprop",
                     year=".header a",                      #zwraca character => mozna zmienic na numeric
                     duration="#overview-top time",         #zwraca character => mozna zmienic na numeric
                     genres=".infobar .itemprop",
                     rating="div.titlePageSprite",
                     votes=".star-box-details a:nth-child(3) span")
      page <- html(link)
      wydlub <- function(node_name){
            item <- page %>% html_nodes( all_nodes[node_name] ) %>% html_text %>% stri_trim
            if( length(item)>0 ) return(item)
            else return(NA)
      }
      info_z_glownej <- lapply(names(all_nodes),wydlub)
      names(info_z_glownej) <- names(all_nodes)
      
      # zmiana formatowania czasu trwania filmu.
      if( length(info_z_glownej$duration)>0 )
            info_z_glownej$duration <- unlist(stri_extract_all_regex(info_z_glownej$duration,"[0-9]+"))  #zwraca character/NA 
      
      # zmiana gatunkow na wiele kolumn
      info_z_glownej$genres <- paste0(info_z_glownej$genres,collapse = sep)
      return(as.data.frame(info_z_glownej))
}

# info z readLines
from_page_source <- function(link, sep=",") {
      page <- readLines(link)
      page <- paste(page, collapse = "")
      znaczniki <- c(production_countries = "(?<=Country:).+?(?=</div)", language = "(?<=Language:).+?(?=</div)", color = "(?<=Color:).+?(?=</a)")
      details <- function(znacznik) {
            item <- unlist(stri_extract_all_regex(page, znacznik))
            if (!is.na(item)) {
                  item <- unlist(stri_extract_all_regex(item, "(?<=itemprop='url'>)([a-zA-Z]| )+"))
                  paste0(item, collapse = sep)
            } else item <- NA
      }
      a <- sapply(znaczniki, details)
      names(a) <- names(znaczniki)
      return(a)
} 

# keywords
keywords <- function(link, sep=",") {
      # przejscie do unikalnej strony z keywords
      key_link <- paste0(link, "/keywords?ref_=tttg_ql_4")
      pages <- html(key_link)
      # keywords
      key_movie <- getNodeSet(pages, "//div[@class='sodatext']") %>% xml_text %>% stri_trim_both
      if (length(key_movie) == 0) 
            return(NA)
      # zwracamy wektor
      vec <- paste0(key_movie, collapse = sep)
      names(vec) <- "keywords"
      return(vec)
} 

pobieraczek <- function(from, to=from){
      
      if(!file.exists(file.path("dane"))){
            # jesli nie, tworzymy takowy
            dir.create(file.path("dane"))
      }
      if(!file.exists(file.path("dane/glowne"))){
            # jesli nie, tworzymy takowy
            dir.create(file.path("dane/glowne"))
      }
      #lista plikow w folderze
      which_to_download <- unlist(sapply(as.character(from:to), 
                                         function(x) list.files(paste0(getwd(),"/movies_link"), 
                                                                x, full.names=TRUE)), 
                                  use.names = FALSE)
      if(length(which_to_download)==0){
            return(invisible(NULL))
      }
      #interesujace nas pliki
      #files<-files[which_to_download]
      names_of_files<-stri_sub(which_to_download,-8,-5)
      names_of_table<-paste0("dane/glowne/",names_of_files,".csv")
      
      for(j in 1:length(names_of_table)){
            
            con <- file(names_of_table[j])
            plik_linkow <- read.table(which_to_download[j],header=TRUE)$link
            liczba_linkow <- length(plik_linkow)
            i=1
            write.table(t(c("title","year","duration","genres","rating","votes","DirectedBy","Cast","Writing","ProducedBy",
                          "MusicBy","CinematographyBy","production_countries","language","color","keywords")),
                        file=names_of_table[j], row.names=FALSE, col.names=FALSE, sep=";")
            open(con,"a+")
            while( i <= liczba_linkow ){
                  link <- as.character(plik_linkow[i])
                  a <- from_main_page(link)
                  b <- from_full_cast_n_crew(link)
                  c <- from_page_source(link)
                  d <- keywords(link)
                  suppressWarnings(
                        write.table(
                              as.data.frame(c(a,b,c,d)),
                              file=names_of_table[j], append=TRUE, sep=";", row.names=FALSE,
                              col.names=FALSE #!file.exists(names_of_table[j])
                        )
                  )
                  rm(a,b,c,d)
                  i=i+1
            } 
            close(con)
      }
      cat("\nDone\n")
}

pobieraczek(1899)

