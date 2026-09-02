package com.redhat.demo.catalog.service;

import com.redhat.demo.catalog.model.Product;

import org.apache.commons.text.StringSubstitutor;
import org.springframework.stereotype.Service;
import org.yaml.snakeyaml.Yaml;

import javax.annotation.PostConstruct;
import java.io.InputStream;
import java.math.BigDecimal;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class CatalogService {

    private final List<Product> products = new ArrayList<>();

    @PostConstruct
    public void loadCatalog() {
        Yaml yaml = new Yaml();
        InputStream stream = getClass().getClassLoader().getResourceAsStream("catalog.yaml");
        if (stream == null) {
            throw new IllegalStateException("catalog.yaml not found on classpath");
        }

        Map<String, Object> data = yaml.load(stream);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) data.get("products");

        Map<String, String> templateValues = new HashMap<>();
        templateValues.put("year", String.valueOf(Calendar.getInstance().get(Calendar.YEAR)));
        templateValues.put("company", "Red Hat");
        StringSubstitutor substitutor = new StringSubstitutor(templateValues);

        for (Map<String, Object> item : items) {
            Product product = new Product();
            product.setId(UUID.fromString((String) item.get("id")));
            product.setName(substitutor.replace((String) item.get("name")));
            product.setDescription(substitutor.replace((String) item.get("description")));
            product.setPrice(new BigDecimal(item.get("price").toString()));
            product.setCategory((String) item.get("category"));
            product.setImageUrl((String) item.get("imageUrl"));

            @SuppressWarnings("unchecked")
            Map<String, Object> meta = (Map<String, Object>) item.get("metadata");
            product.setMetadata(meta != null ? meta : Map.of());

            products.add(product);
        }
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
