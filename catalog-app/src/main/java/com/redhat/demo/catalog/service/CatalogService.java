package com.redhat.demo.catalog.service;

import com.jayway.jsonpath.JsonPath;
import com.redhat.demo.catalog.model.Product;

import org.json.JSONObject;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamReader;
import java.io.InputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class CatalogService {

    private final List<Product> products = new ArrayList<>();
    private final Map<String, String> categoryDescriptions = new LinkedHashMap<>();

    @PostConstruct
    public void loadCatalog() {
        Map<String, String> templateVars = loadConfig();
        templateVars.put("year", String.valueOf(Calendar.getInstance().get(Calendar.YEAR)));
        loadProducts(templateVars);
    }

    private Map<String, String> loadConfig() {
        Map<String, String> vars = new LinkedHashMap<>();
        try (InputStream is = new ClassPathResource("config.xml").getInputStream()) {
            XMLInputFactory factory = XMLInputFactory.newFactory();
            XMLStreamReader reader = factory.createXMLStreamReader(is);
            while (reader.hasNext()) {
                int event = reader.next();
                if (event == XMLStreamReader.START_ELEMENT) {
                    String name = reader.getLocalName();
                    if ("var".equals(name)) {
                        String key = reader.getAttributeValue(null, "name");
                        String value = reader.getAttributeValue(null, "value");
                        if (key != null && value != null) {
                            vars.put(key, value);
                        }
                    } else if ("category".equals(name)) {
                        String catName = reader.getAttributeValue(null, "name");
                        String desc = reader.getAttributeValue(null, "description");
                        if (catName != null && desc != null) {
                            categoryDescriptions.put(catName, desc);
                        }
                    }
                }
            }
            reader.close();
        } catch (Exception e) {
            vars.put("company", "Red Hat");
        }
        return vars;
    }

    private void loadProducts(Map<String, String> templateVars) {
        try (InputStream is = new ClassPathResource("catalog.json").getInputStream()) {
            String json = new String(is.readAllBytes(), StandardCharsets.UTF_8);
            List<Map<String, Object>> items = JsonPath.read(json, "$.products[*]");

            for (Map<String, Object> item : items) {
                JSONObject obj = new JSONObject(item);
                Product product = new Product();
                product.setId(UUID.fromString(obj.getString("id")));
                product.setName(applyTemplateVars(obj.getString("name"), templateVars));
                product.setDescription(applyTemplateVars(obj.getString("description"), templateVars));
                product.setPrice(obj.getBigDecimal("price"));
                product.setCategory(obj.getString("category"));
                product.setImageUrl(obj.getString("imageUrl"));

                if (obj.has("metadata")) {
                    product.setMetadata(obj.getJSONObject("metadata").toMap());
                } else {
                    product.setMetadata(Map.of());
                }

                products.add(product);
            }
        } catch (Exception e) {
            throw new IllegalStateException("Failed to load catalog.json", e);
        }
    }

    private String applyTemplateVars(String text, Map<String, String> vars) {
        for (Map.Entry<String, String> entry : vars.entrySet()) {
            text = text.replace("${" + entry.getKey() + "}", entry.getValue());
        }
        return text;
    }

    public List<Product> findAll() {
        return Collections.unmodifiableList(products);
    }

    public Optional<Product> findById(UUID id) {
        return products.stream()
                .filter(p -> p.getId().equals(id))
                .findFirst();
    }

    public List<Product> findByCategory(String category) {
        return products.stream()
                .filter(p -> p.getCategory().equalsIgnoreCase(category))
                .collect(Collectors.toList());
    }
}
