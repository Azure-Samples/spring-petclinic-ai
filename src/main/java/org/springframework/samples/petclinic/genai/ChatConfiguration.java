/*
 * Copyright 2012-2024 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.samples.petclinic.genai;

import org.springframework.ai.azure.openai.AzureOpenAiChatModel;
import org.springframework.ai.azure.openai.AzureOpenAiChatOptions;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.ChatClientCustomizer;
import org.springframework.ai.chat.client.advisor.PromptChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.InMemoryChatMemory;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.embedding.EmbeddingModel;
import org.springframework.ai.model.function.FunctionCallbackContext;
import org.springframework.ai.vectorstore.SearchRequest;
import org.springframework.ai.vectorstore.SimpleVectorStore;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.Resource;
import org.springframework.samples.petclinic.conditions.ConditionalOnPropertyNotEmpty;

import com.azure.ai.openai.OpenAIClientBuilder;
import com.azure.core.credential.AzureKeyCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;

@Profile({ "!test" })
@Configuration
@EnableConfigurationProperties({ ChatAuthProperties.class, ChatOptionsProperties.class })
class ChatConfiguration {

	@Value("classpath:/prompts/system.st")
	private Resource systemResource;

	@Autowired
	private ApplicationContext applicationContext;

	/**
	 * Configure a bean of type AzureOpenAiChatModel as ChatModel
	 */
	@Bean
	@ConditionalOnProperty(ChatOptionsProperties.PREFIX + ".deployment-name")
	public AzureOpenAiChatModel chatModel(OpenAIClientBuilder openAIClientBuilder, ChatOptionsProperties properties) {
		var openAIChatOptions = AzureOpenAiChatOptions.builder()
			.withDeploymentName(properties.getDeploymentName())
			.withTemperature(properties.getTemperature())
			.build();

		// provide Context to load function callbacks
		var functionCallbackContext = new FunctionCallbackContext();
		functionCallbackContext.setApplicationContext(applicationContext);

		return new AzureOpenAiChatModel(openAIClientBuilder, openAIChatOptions, functionCallbackContext);
	}

	/**
	 * Configure a bean of type OpenAIClient, which is used to construct ChatModel and
	 * EmbeddingModel
	 */
	@Bean
	@ConditionalOnPropertyNotEmpty(ChatAuthProperties.PREFIX + ".client-id")
	public OpenAIClientBuilder openAIClientManagedIdentity(ChatAuthProperties properties) {
		return new OpenAIClientBuilder().endpoint(properties.getEndpoint())
			.credential(new DefaultAzureCredentialBuilder().managedIdentityClientId(properties.getClientId()).build());
	}

	@Bean
	@ConditionalOnPropertyNotEmpty(ChatAuthProperties.PREFIX + ".api-key")
	public OpenAIClientBuilder openAIClientApiKey(ChatAuthProperties properties) {
		return new OpenAIClientBuilder().endpoint(properties.getEndpoint())
			.credential(new AzureKeyCredential(properties.getApiKey()));
	}

	/**
	 * Configure a bean of type ChatClient
	 */
	@Bean
	public ChatClient chatClient(ChatClient.Builder chatClientBuilder) {
		return chatClientBuilder.build();
	}

	/**
	 * Configure a bean of type ChatClientCustomizer
	 * @param vectorStore: configured below
	 * @param model: auto-configured in application properties
	 */
	@Bean
	public ChatClientCustomizer chatClientCustomizer(VectorStore vectorStore, ChatModel model) {
		// use a in-memory storage to track context and chat history between user
		// interactions
		ChatMemory chatMemory = new InMemoryChatMemory();
		// use PromptChatMemoryAdvisor to access the stored conversation memory
		// use ModeledQuestionAnswerAdvisor to process user queries before retrieving
		// relevant documents
		return b -> b.defaultSystem(systemResource)
			.defaultFunctions("listOwners", "listVets", "addPetToOwner", "addOwnerToPetclinic")
			.defaultAdvisors(new PromptChatMemoryAdvisor(chatMemory),
					new ModeledQuestionAnswerAdvisor(vectorStore, SearchRequest.defaults(), model));
	}

	/**
	 * Configure a bean of type VectorStore, which is used to store the semantic vectors
	 * (embeddings).
	 * @param embeddingModel: auto-configured in application properties
	 */
	@Bean
	public VectorStore simpleVectorStore(EmbeddingModel embeddingModel) {
		return new SimpleVectorStore(embeddingModel);
	}

}
