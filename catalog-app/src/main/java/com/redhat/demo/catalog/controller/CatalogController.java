package com.redhat.demo.catalog.controller;

import com.redhat.demo.catalog.model.Product;
import com.redhat.demo.catalog.service.CatalogService;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import org.json.JSONObject;

import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class CatalogController {

    private final CatalogService catalogService;

    @Value("${app.profile:unknown}")
    private String activeProfile;

    @Value("${app.version:1.0.0}")
    private String appVersion;

    @Value("${app.bom-path:/deployments/bom.json}")
    private String bomPath;

    public CatalogController(CatalogService catalogService) {
        this.catalogService = catalogService;
    }

    @GetMapping("/products")
    public List<Product> listProducts(
            @RequestParam(required = false) String category) {
        if (category != null && !category.isBlank()) {
            return catalogService.findByCategory(category);
        }
        return catalogService.findAll();
    }

    @GetMapping("/products/{id}")
    public ResponseEntity<Product> getProduct(@PathVariable UUID id) {
        return catalogService.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("status", "UP");
        info.put("profile", activeProfile);
        info.put("version", appVersion);
        info.put("timestamp", Instant.now().toString());
        info.put("java", System.getProperty("java.version"));

        Map<String, String> dependencies = new LinkedHashMap<>();
        dependencies.put("woodstox-core", getPackageVersion("com.fasterxml.woodstox", "woodstox-core"));
        dependencies.put("json-path", getPackageVersion("com.jayway.jsonpath", "json-path"));
        dependencies.put("json", getPackageVersion("org.json", "json"));
        dependencies.put("spring-core", getPackageVersion("org.springframework", "spring-core"));
        info.put("dependencies", dependencies);

        return info;
    }

    @PostMapping("/products/import")
    public ResponseEntity<Map<String, Object>> importProducts(@RequestBody String body) {
        try {
            XMLInputFactory factory = XMLInputFactory.newFactory();
            XMLStreamReader reader = factory.createXMLStreamReader(new StringReader(body));
            int count = 0;
            while (reader.hasNext()) {
                int event = reader.next();
                if (event == XMLStreamReader.START_ELEMENT && "product".equals(reader.getLocalName())) {
                    count++;
                }
            }
            reader.close();
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("status", "success");
            result.put("imported", count);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("status", "error");
            result.put("message", e.getClass().getSimpleName() + ": " + e.getMessage());
            return ResponseEntity.status(500).body(result);
        }
    }

    @GetMapping(value = "/dependencies", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> getDependencies() {
        try {
            Path path = Path.of(bomPath);
            if (Files.exists(path)) {
                return ResponseEntity.ok(Files.readString(path, StandardCharsets.UTF_8));
            }
            ClassPathResource resource = new ClassPathResource("bom.json");
            if (resource.exists()) {
                try (InputStream is = resource.getInputStream()) {
                    return ResponseEntity.ok(new String(is.readAllBytes(), StandardCharsets.UTF_8));
                }
            }
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    private String getPackageVersion(String groupId, String artifactId) {
        try {
            String path = "META-INF/maven/" + groupId + "/" + artifactId + "/pom.properties";
            ClassPathResource resource = new ClassPathResource(path);
            if (resource.exists()) {
                Properties props = new Properties();
                props.load(resource.getInputStream());
                return props.getProperty("version", "unknown");
            }
        } catch (IOException ignored) {
        }
        return "unknown";
    }
}
