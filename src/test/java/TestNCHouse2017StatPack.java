import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Test;
import org.openqa.selenium.By;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;
import org.openqa.selenium.chrome.ChromeDriver;
import org.openqa.selenium.chrome.ChromeOptions;
import org.openqa.selenium.support.ui.ExpectedConditions;
import org.openqa.selenium.support.ui.WebDriverWait;

import java.util.List;

import static junit.framework.TestCase.assertTrue;

//Test of the NCHouse2017StatPack pdf file, it will go through various user scenarios to test the functionality of the regex
// implementation (spanning pages, multiple search results, inclusive and non-inclusive, and overlap)
// @author SM modified: 4/28/18

public class TestNCHouse2017StatPack {
    private static WebDriver driver;
    private static String Tabula_url = "http://127.0.0.1:9292/";
    private WebDriverWait wait = new WebDriverWait(driver, 500);

    //will continue to refresh the page until it sees one of the buttons appear in the menu option of the extraction page
    private void PageRefresh() throws InterruptedException {
        //menu options did not fully load
        Thread.sleep(1000);
        //refresh the page
        while(driver.findElements( By.id("restore-detected-tables")).size() == 0) {
            driver.navigate().refresh();
            Thread.sleep(700);
        }
    }
    //will navigate and wait for the data to appear in the preview and export data page
    private void PreviewandExportDatapg(){
        By previewandexport_id = By.id("all-data");
        WebElement previewandexport_button = wait.until(ExpectedConditions.visibilityOfElementLocated(previewandexport_id));
        previewandexport_button.click();
        wait.until(ExpectedConditions.visibilityOfElementLocated(By.className("detection-row")));
    }
    //will wait for the regex button to become clickable and then click the regex button
    private void ClickRegexButton() throws InterruptedException {
        By regex_search_id = By.id("regex-search");
        WebElement regex_button = new WebDriverWait(driver, 30).until(ExpectedConditions.
                elementToBeClickable(regex_search_id));
        regex_button.click();
        Thread.sleep(800);
    }
    //send regex inputs to the corresponding pattern type
    private void PatternInputStrings(String pattern_before, String pattern_after){
        By pattern_before_input = By.id("pattern_before");
        By pattern_after_input = By.id("pattern_after");
        driver.findElement(pattern_before_input).sendKeys(pattern_before);
        driver.findElement(pattern_after_input).sendKeys(pattern_after);
    }
    //send corresponding info of inclusive to the pattern type
    private void InclusiveButtons(boolean patternbefore, boolean patternafter){
        WebElement inclusive_before_btn = new WebDriverWait(driver, 30).
                until(ExpectedConditions.elementToBeClickable(driver.findElement(By.id("include_pattern_before"))));
        WebElement inclusive_after_btn = new WebDriverWait(driver, 30).
                until(ExpectedConditions.elementToBeClickable(driver.findElement(By.id("include_pattern_after"))));
        if (patternbefore){
            inclusive_before_btn.click(); }
        if(patternafter){
            inclusive_after_btn.click(); }
    }
    //go on and upload the pdf file
    private void UploadPDF() throws InterruptedException {
        String filePath = System.getProperty("user.dir") + "/src/test/pdf/NC_HOUSE_2017_Stat_Pack_8.21.17.pdf";
        WebElement chooseFile = driver.findElement(By.id("file"));
        chooseFile.sendKeys(filePath);
        Thread.sleep(1000);
        WebElement import_btn = driver.findElement(By.id("import_file"));
        import_btn.click();
        Thread.sleep(5000);
        wait.until(ExpectedConditions.elementToBeClickable(By.id("restore-detected-tables")));
    }
    //delete the pdf file
    private void DeletePDF(){
        //navigates back and deletes the pdf utilized
        driver.findElement(By.id("delete_pdf")).click();
        driver.switchTo().alert().accept();
    }
    //instantiation of Tabula
    @BeforeClass
    public static void SetUp(){
        System.setProperty("webdriver.chrome.driver","/usr/local/bin/chromedriver");
        ChromeOptions options = new ChromeOptions();
        options.addArguments("headless");
        options.addArguments("no-sandbox");

        //set up of chromdriver and navigation to the url, as well as uploading of the pdf file
        driver = new ChromeDriver(options);
        driver.get(Tabula_url);
        driver.manage().window().maximize();

    }
    //test of 3 different instances of inputting regex searches with 3 different types of inclusive combinations to
    // get multiple regex results
    @Test
    public void TestInclusivePatternswithRegexSearches() {
        try{
            UploadPDF();
            PageRefresh();

            //Tests for inclusive for pattern before and non-inclusive for pattern after
            PatternInputStrings("2017 House Redistricting","69");
            InclusiveButtons(true, false);
            ClickRegexButton();
            wait.until(ExpectedConditions.visibilityOfElementLocated(By.className("regex-result")));
            // Thread.sleep(5000);
            String result = driver.findElement(By.xpath(".//*[@class='regex-results-table']//td[contains(.,'14')]")).getText();
            Boolean regex_result;
            if(result.equals("14")){ regex_result = true;} //if true, there are zero matches
            else{ regex_result = false;}
            PreviewandExportDatapg();
            String result_data = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'2017 House Redistricting Plan: Population Deviation')]")).getText();
            Boolean regex_data;
            if(result_data.equals("2017 House Redistricting Plan: Population Deviation")){ regex_data = true;}
            else{ regex_data = false;}
            Thread.sleep(600);
            String result_data2 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'District')]")).getText();
            Boolean regex_data2;
            if(result_data2.equals("District 2010 Pop")){ regex_data2 = true;}
            else{ regex_data2 = false;}
            Boolean final_results;
            if(regex_result && regex_data && regex_data2){ final_results = true;}
            else{final_results = false;}
            assertTrue("Failed, Tabula found no match for inclusive for pattern before and non-inclusive for " +
                    "pattern after", final_results);
            driver.navigate().refresh();
            PageRefresh();

            //Tests for non-inclusive for pattern before and inclusive for pattern after
            PatternInputStrings("2017 House Redistricting", "69");
            InclusiveButtons(false, true);
            ClickRegexButton();
            wait.until(ExpectedConditions.visibilityOfElementLocated(By.className("regex-result")));
            String result2 = driver.findElement(By.xpath(".//*[@class='regex-results-table']//td[contains(.,'14')]")).getText();
            Boolean regex_result3;
            if(result2.equals("14")){ regex_result3 = true;} //if true, there are zero matches
            else{ regex_result3 = false;}
            PreviewandExportDatapg();
            String result_data3 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'District')]")).getText();
            Boolean regex_data3;
            if(result_data3.equals("District")){ regex_data3 = true;}
            else{ regex_data3 = false;}
            Thread.sleep(600);
            String result_data4 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.,'105')]")).getText();
            Boolean regex_data4;
            if(result_data4.equals("105")){ regex_data4 = true;}
            else{ regex_data4 = false;}
            Boolean final_results2;
            if(regex_result3 && regex_data3 && regex_data4){ final_results2 = true;}
            else{final_results2 = false;}
            assertTrue("Failed, Tabula found no match for inclusive for pattern after and non-inclusive for " +
                    "pattern before", final_results2);
            driver.navigate().refresh();
            PageRefresh();

            //Tests for inclusive for pattern before and for pattern after
            PatternInputStrings("2017 House Redistricting","69");
            InclusiveButtons(true, true);
            ClickRegexButton();
            wait.until(ExpectedConditions.visibilityOfElementLocated(By.className("regex-result")));
            String result3 = driver.findElement(By.xpath(".//*[@class='regex-results-table']//td[contains(.,'14')]")).getText();
            Boolean regex_result4;
            if(result3.equals("14")){ regex_result4 = true;} //if true, there are zero matches
            else{ regex_result4 = false;}
            PreviewandExportDatapg();
            String result_data5 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'2017 House Redistricting Plan: Population Deviation')]")).getText();
            Boolean regex_data5;
            if(result_data5.equals("2017 House Redistricting Plan: Population Deviation")){ regex_data5 = true;}
            else{ regex_data5 = false;}
            Thread.sleep(600);
            String result_data6 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'105 22,913 55.44% 17,133 41.45% 1,287 3.11%')]")).getText();
            Boolean regex_data6;
            if(result_data6.equals("105 22,913 55.44% 17,133 41.45% 1,287 3.11%")){ regex_data6 = true;}
            else{ regex_data6 = false;}
            Boolean final_results3;
            if(regex_result4 && regex_data5 && regex_data6){ final_results3 = true;}
            else{final_results3 = false;}
            assertTrue("Failed, Tabula found no match for inclusive for pattern after and inclusive for " +
                    "pattern before", final_results3);
            driver.navigate().back();
            driver.navigate().back();
            Thread.sleep(500);
            DeletePDF();
        }catch(Exception e){
            System.out.print(e);
        }
    }
    //test of 2 different instances of inputting regex to get a multi spanning table
    @Test
    public void TestMultiPageTables(){
        try {
            //Test for a multi spanning page of 2 pages that is found 7 times in the file
            UploadPDF();
            PageRefresh();

            PatternInputStrings("District", "District");
            InclusiveButtons(false, true);
            ClickRegexButton();
            wait.until(ExpectedConditions.visibilityOfElementLocated(By.className("regex-result")));
            String result = driver.findElement(By.xpath(".//*[@class='regex-results-table']//td[contains(.,'7')]")).getText();
            Boolean regex_result;
            if (result.equals("7")) {
                regex_result = true;
            } //if true, there is a match
            else {
                regex_result = false;
            }
            PreviewandExportDatapg();
            String result_data = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'1')]")).getText();
            Boolean regex_data;
            if (result_data.equals("1")) {
                regex_data = true;
            } else {
                regex_data = false;
            }
            String result_data2 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'District Rep Rep % Dem Dem % Lib Lib %')]")).getText();
            Boolean regex_data2;
            if (result_data2.equals("District Rep Rep % Dem Dem % Lib Lib % Write-In Write-In %")) {
                regex_data2 = true;
            } else {
                regex_data2 = false;
            }
            Boolean final_results;
            if (regex_result && regex_data && regex_data2) {
                final_results = true;
            } else {
                final_results = false;
            }
            assertTrue("Failed, Tabula found no match for the multi-page table", final_results);

            driver.navigate().back();
            driver.navigate().back();
            Thread.sleep(500);
            DeletePDF();
        }catch (Exception e){
            System.out.print(e);
        }
    }
    //test of an overlapping instance where it checks that there is only one regex result after attempting an overlap
    @Test
    public void TestOverlapRegexSearch() {
        try{
            //Test for overlapping regex searches
            UploadPDF();
            PageRefresh();

            PatternInputStrings("District", "Total");
            ClickRegexButton();
            Thread.sleep(5000);
            PatternInputStrings("2017 House", "District");
            InclusiveButtons(false, true);
            ClickRegexButton();
            Thread.sleep(5000);
            driver.switchTo().alert().accept(); //accept error pop-up window
            //Checks that there is only one regex result, since it shouldn't had allowed for 2 results to appear since the
            // 2nd one causes an overlap
            Thread.sleep(2000);
            List<WebElement> regex_rows = driver.findElements(By.className("regex-result"));
            int regex_count = regex_rows.size();
            int regex_count1 = 1;
            assertTrue("Failed, Tabula found more than one match for an overlap regex search",
                    (regex_count1 == regex_count ));
            PreviewandExportDatapg();
            String result_data = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.," +
                    "'83')]")).getText();
            Boolean regex_data;
            if (result_data.equals("83")) { regex_data = true;
            } else { regex_data = false; }
            String result_data2 = driver.findElement(By.xpath(".//*[@id='extracted-table']//td[contains(.,'120')]")).getText();
            Boolean regex_data2;
            if (result_data2.equals("120")) { regex_data2 = true;
            } else { regex_data2 = false; }
            Boolean final_results;
            if (regex_data && regex_data2) { final_results = true;
            } else { final_results = false; }
            assertTrue("Failed, Tabula found no match for the multi-page table", final_results);
            driver.navigate().back();
            driver.navigate().back();
            Thread.sleep(500);
            DeletePDF();
        }catch (Exception e){
            System.out.print(e);
        }
    }
    @AfterClass
    public static void TearDown(){
        driver.quit();
    }
}
